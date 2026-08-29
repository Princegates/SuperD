-- SuperD: rewards a driver's track record when automatic assignment can't
-- find anyone nearby. Two tiers now, instead of one flat "nearest driver,
-- however far" search:
--
--   1. Nearest online, eligible driver within
--      app_settings.auto_assign_radius_km of the vendor's pickup point -
--      the same candidate filters as before (active, not frozen, online,
--      a live location fix in the last 15 minutes, today's commission
--      paid, under the per-driver assignment cap).
--   2. Only if tier 1 finds nobody: the same candidate pool with no
--      radius limit at all, ranked by track record instead of distance -
--      highest average customer rating on their completed deliveries
--      first (a driver with no ratings yet ranks behind anyone who has
--      at least one), then most completed deliveries as a tiebreak, then
--      distance. This is the "recognize high performing drivers"
--      fallback - a delivery only reaches for someone far away because
--      they've earned it, and only once the normal nearby-driver search
--      comes up empty (rather than leaving the delivery pending).
--
-- Same signature as `0051_vehicle_types.sql`'s version - only the
-- driver-matching block changes, so a plain `create or replace` is
-- enough (no drop/re-grant needed).

alter table public.app_settings
  add column if not exists auto_assign_radius_km numeric(10, 2) not null default 8;

alter table public.app_settings
  drop constraint if exists app_settings_auto_assign_radius_km_check,
  add constraint app_settings_auto_assign_radius_km_check
    check (auto_assign_radius_km between 1 and 100);

comment on column public.app_settings.auto_assign_radius_km is 'How far (km) from the vendor automatic assignment searches for the nearest driver before falling back to the best-rated available driver regardless of distance. Always 1-100.';

-- A driver's average customer rating across their completed, rated
-- deliveries - null if they have none yet. Used by the fallback tier
-- below, and reusable for an admin-facing "top performer" display.
create or replace function public.driver_average_rating(p_driver_id uuid)
returns numeric
language sql
security definer
set search_path = public
stable
as $$
  select avg(rating)::numeric
  from public.deliveries
  where assigned_driver_id = p_driver_id and rating is not null;
$$;

grant execute on function public.driver_average_rating(uuid) to authenticated;

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
  customer_email text default null,
  p_vehicle_type_id uuid default null
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
  v_vehicle_extra_fee numeric;
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
  radius_km numeric;
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;

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

  select extra_fee into v_vehicle_extra_fee
  from public.vehicle_types where id = p_vehicle_type_id;
  v_vehicle_extra_fee := coalesce(v_vehicle_extra_fee, 0);

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

  amount := v_base_fare + v_price_per_km * distance_km + v_vehicle_extra_fee;

  is_due_soon := scheduled_at is null or scheduled_at <= now() + interval '15 minutes';
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);
  radius_km := coalesce(s.auto_assign_radius_km, 8);

  if v.location_lat is not null and v.location_lng is not null and is_due_soon then
    -- Tier 1: nearest eligible, online driver within the vendor's normal
    -- auto-assign radius - see 0044_proximity_based_auto_assignment.sql
    -- for the original (unbounded) version of this search.
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
      and 6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(p.last_lat))
        + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(v.location_lng))
      ))) <= radius_km
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(p.last_lat))
        + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(v.location_lng))
      ))) asc,
      p.full_name
    limit 1;

    -- Tier 2: nobody eligible within radius_km - reward whichever online
    -- eligible driver anywhere has the best track record instead of
    -- leaving this pending. A driver with no ratings yet (coalesced to
    -- -1) always loses to one with at least a single rating.
    if target_driver_id is null then
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
        coalesce(public.driver_average_rating(p.id), -1) desc,
        (
          select count(*) from public.deliveries d
          where d.assigned_driver_id = p.id and d.status = 'delivered'
        ) desc,
        6371 * acos(least(1.0, greatest(-1.0,
          sin(radians(v.location_lat)) * sin(radians(p.last_lat))
          + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
            * cos(radians(p.last_lng) - radians(v.location_lng))
        ))) asc,
        p.full_name
      limit 1;
    end if;
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
