-- SuperD: automatic driver matching now picks whichever online, eligible
-- driver is physically CLOSEST to the vendor right now (using their live
-- GPS position - profiles.last_lat/last_lng, pushed every ~15s by the
-- driver's own app while it's open, see DriverDashboardScreen) instead of
-- matching on a driver's manually-set zone_id. This replaces the
-- zone-matching rule from 0033_zone_auto_recognition_and_cap.sql for BOTH
-- places a driver gets auto-picked:
--
--   1. submit_delivery_request() - a new order.
--   2. driver_cancel_delivery() - a driver bails mid-trip; the
--      replacement is whoever's closest to the CANCELLING driver's own
--      last known position (the package is already with them, so that's
--      the relevant point, not the vendor).
--
-- Why: a driver's zone_id has to be set by hand and kept up to date -
-- forgetting it (as happened in testing) silently breaks automatic
-- assignment entirely with no obvious symptom. Live location is already
-- being collected for the Live Map/customer tracking, needs no extra
-- admin step per driver, and picks a genuinely closer driver instead of
-- just whoever happens to be tagged with the right zone name.
--
-- zone_id (on both deliveries and profiles) is untouched and still used
-- for pricing (zone-specific base_fare/price_per_km) and reporting -
-- only *driver matching* stops using it. app_settings.zone_auto_assign_cap
-- keeps its name and 3-20 range, but now caps a driver's overall active
-- deliveries rather than same-zone ones specifically.
--
-- A driver whose last location update is older than 15 minutes is
-- treated as effectively offline for matching purposes, even if
-- is_online is still true (their app most likely isn't actually running
-- - it pushes far more often than that while it is). Same 15-minute
-- cutoff Profile.hasRecentLocation already uses for the Live Map and the
-- Console's manual driver-ranking hint, so "recent enough to trust" means
-- the same thing everywhere in the app.

-- Same signature as 0043's version - only the driver-matching block
-- changes; zone detection/pricing above it is untouched.
create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null,
  road_distance_km double precision default null,
  scheduled_at timestamptz default null,
  customer_email text default null
)
returns table (
  tracking_code text,
  quoted_amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vendors%rowtype;
  s public.app_settings%rowtype;
  z public.zones%rowtype;
  v_base_fare numeric;
  v_price_per_km numeric;
  new_tracking_code text;
  straight_line_km double precision;
  distance_km double precision;
  amount numeric(10, 2);
  cos_angle double precision;
  resolved_zone_id uuid;
  target_driver_id uuid;
  target_status public.delivery_status;
  target_assigned_at timestamptz;
  is_due_soon boolean;
  assign_cap integer;
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;

  -- Zone is still resolved and stored - it drives pricing and reporting,
  -- just not which driver gets picked (below).
  resolved_zone_id := v.zone_id;
  if dropoff_lat is not null and dropoff_lng is not null then
    resolved_zone_id := coalesce(
      public.detect_zone_for_point(dropoff_lat, dropoff_lng),
      v.zone_id
    );
  end if;

  if resolved_zone_id is not null then
    select * into z from public.zones where id = resolved_zone_id;
  end if;

  v_base_fare := coalesce(z.base_fare, s.base_fare, 0);
  v_price_per_km := coalesce(z.price_per_km, s.price_per_km, 0);

  if dropoff_lat is not null and dropoff_lng is not null
     and v.location_lat is not null and v.location_lng is not null then
    cos_angle := sin(radians(v.location_lat)) * sin(radians(dropoff_lat))
      + cos(radians(v.location_lat)) * cos(radians(dropoff_lat))
        * cos(radians(dropoff_lng) - radians(v.location_lng));
    straight_line_km := 6371 * acos(least(1.0, greatest(-1.0, cos_angle)));
  else
    straight_line_km := 0;
  end if;

  distance_km := greatest(coalesce(road_distance_km, 0), straight_line_km);

  amount := least(v_base_fare + v_price_per_km * distance_km, 50);

  is_due_soon := scheduled_at is null or scheduled_at <= now() + interval '15 minutes';
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);

  -- Whichever online, eligible driver is physically closest to the
  -- vendor's pickup point right now - see the migration header comment.
  -- Skipped entirely (falls to 'pending') if the vendor has no
  -- coordinates to measure from, same as always for a delivery
  -- scheduled well into the future.
  if v.location_lat is not null and v.location_lng is not null and is_due_soon then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.last_lat is not null
      and p.last_lng is not null
      and p.location_updated_at is not null
      and p.location_updated_at > now() - interval '15 minutes'
      and public.driver_daily_fee_paid(p.id)
      and (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.status not in ('delivered', 'cancelled')
      ) < assign_cap
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(p.last_lat))
        + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(v.location_lng))
      ))) asc,
      p.full_name
    limit 1;
  end if;

  if target_driver_id is not null then
    target_status := 'assigned';
    target_assigned_at := now();
  else
    target_status := 'pending';
    target_assigned_at := null;
  end if;

  insert into public.deliveries (
    customer_name, customer_phone, customer_email,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    vendor_id, zone_id, created_by,
    assigned_driver_id, status, assigned_at,
    scheduled_at, auto_assigned
  )
  values (
    customer_name, customer_phone, customer_email,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, resolved_zone_id, null,
    target_driver_id, target_status, target_assigned_at,
    scheduled_at, target_driver_id is not null
  )
  returning deliveries.tracking_code into new_tracking_code;

  if amount > 0 then
    insert into public.payments (delivery_id, amount, currency)
    select id, amount, coalesce(s.currency, 'GHS')
    from public.deliveries
    where deliveries.tracking_code = new_tracking_code;
  end if;

  return query select new_tracking_code, amount, coalesce(s.currency, 'GHS');
end;
$$;

-- Same signature as 0042's version - only the reassignment-candidate
-- block changes, from "nearest same-zone driver by workload" to "nearest
-- driver to the cancelling driver's own last known position".
create or replace function public.driver_cancel_delivery(
  p_delivery_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.deliveries%rowtype;
  s public.app_settings%rowtype;
  old_driver_name text;
  new_driver_name text;
  target_driver_id uuid;
  target_status public.delivery_status;
  assign_cap integer;
  reason_suffix text;
  note_text text;
  origin_lat double precision;
  origin_lng double precision;
begin
  select * into d from public.deliveries
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status in ('picked_up', 'in_transit')
  for update;

  if not found then
    raise exception 'This delivery can no longer be cancelled - it may already have been delivered or reassigned.';
  end if;

  select full_name, last_lat, last_lng
    into old_driver_name, origin_lat, origin_lng
  from public.profiles where id = auth.uid();

  select * into s from public.app_settings limit 1;
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);

  reason_suffix := case
    when p_reason is not null and length(trim(p_reason)) > 0
      then ' (' || trim(p_reason) || ')'
    else ''
  end;

  -- Nearest online, eligible driver to the cancelling driver's own last
  -- known position - the package is already with them, so that's the
  -- relevant point to measure from, not the vendor. Skipped (falls to
  -- 'pending') if the cancelling driver has no live location of their own
  -- to measure from.
  if origin_lat is not null and origin_lng is not null then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.id <> auth.uid()
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.last_lat is not null
      and p.last_lng is not null
      and p.location_updated_at is not null
      and p.location_updated_at > now() - interval '15 minutes'
      and public.driver_daily_fee_paid(p.id)
      and (
        select count(*) from public.deliveries dd
        where dd.assigned_driver_id = p.id
          and dd.status not in ('delivered', 'cancelled')
      ) < assign_cap
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(origin_lat)) * sin(radians(p.last_lat))
        + cos(radians(origin_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(origin_lng))
      ))) asc,
      p.full_name
    limit 1;
  end if;

  if target_driver_id is not null then
    select full_name into new_driver_name from public.profiles where id = target_driver_id;
    target_status := 'assigned';
    note_text := format(
      'Cancelled by %s mid-trip%s - reassigned to %s.',
      coalesce(old_driver_name, 'the driver'), reason_suffix,
      coalesce(new_driver_name, 'another driver')
    );
  else
    target_status := 'pending';
    note_text := format(
      'Cancelled by %s mid-trip%s - no other driver available, needs manual reassignment.',
      coalesce(old_driver_name, 'the driver'), reason_suffix
    );
  end if;

  perform set_config('superd.status_note', note_text, true);

  update public.deliveries
  set status = target_status,
      assigned_driver_id = target_driver_id,
      assigned_at = null,
      picked_up_at = null,
      auto_assigned = (target_driver_id is not null)
  where id = p_delivery_id;
end;
$$;
