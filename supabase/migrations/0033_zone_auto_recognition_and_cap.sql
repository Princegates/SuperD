-- SuperD: two changes to how a customer-submitted delivery picks its zone
-- and its driver.
--
-- 1. Zone auto-recognition. Until now a delivery's zone_id was always
--    just copied from the vendor's own registered zone - fine for a
--    vendor entirely inside one zone, wrong the moment a vendor's
--    customers span a wider area than the vendor's own pin. Now it's
--    detected from the CUSTOMER's actual drop-off coordinates instead,
--    by finding the nearest zone_location (the named reference points a
--    super admin pins in Console > Zones) within a reasonable distance -
--    see detect_zone_for_point() below. If nothing is close enough (or
--    the request has no coordinates at all), it falls back to the
--    vendor's own zone as before; if that's also unset, the delivery
--    simply has no zone and waits at 'pending' for a dispatcher, exactly
--    like today.
--
-- 2. A cap on automatic assignment. Auto-assignment used to hand a
--    zone's requests to whichever eligible driver already had the most
--    active jobs there, with no ceiling - in a busy zone that driver
--    could end up as the only one ever auto-assigned. app_settings.
--    zone_auto_assign_cap (a super admin sets 3-20, default 5) now stops
--    a driver being picked automatically once they already have that
--    many active deliveries in the zone; once every eligible driver is
--    at the cap, the request lands at 'pending' for a dispatcher to
--    place by hand, same as when nobody in the zone is online at all.

alter table public.app_settings
  add column if not exists zone_auto_assign_cap integer not null default 5;

alter table public.app_settings
  drop constraint if exists app_settings_zone_auto_assign_cap_check,
  add constraint app_settings_zone_auto_assign_cap_check
    check (zone_auto_assign_cap between 3 and 20);

comment on column public.app_settings.zone_auto_assign_cap is 'Max active same-zone deliveries a driver can hold before automatic assignment stops picking them and a new request waits for a dispatcher instead. Always 3-20 - this is a ceiling on automation, not a cap on how much work a driver can be given by hand.';

-- Nearest zone to a point, if one is close enough to trust. Distance is
-- plain haversine (same formula already used for pricing elsewhere in
-- this file/project) against every named zone_location that has
-- coordinates - fast enough at the scale this app runs at without
-- needing PostGIS or a spatial index; add more zone_locations per zone
-- (Console > Zones) to make this more accurate, not more code.
create or replace function public.detect_zone_for_point(
  p_lat double precision,
  p_lng double precision,
  p_max_km double precision default 5
)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select zone_id
  from (
    select
      zl.zone_id,
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(p_lat)) * sin(radians(zl.lat))
        + cos(radians(p_lat)) * cos(radians(zl.lat))
          * cos(radians(zl.lng) - radians(p_lng))
      ))) as distance_km
    from public.zone_locations zl
    where zl.lat is not null and zl.lng is not null
  ) nearest
  where distance_km <= p_max_km
  order by distance_km asc
  limit 1
$$;

grant execute on function public.detect_zone_for_point(double precision, double precision, double precision) to anon, authenticated;

-- get_delivery_price_estimate() picks up the same zone-detection change
-- as submit_delivery_request() below, so the estimate a customer sees
-- before submitting matches what they're actually charged after -
-- same signature as 0028's version, only the body changes.
create or replace function public.get_delivery_price_estimate(
  p_code text,
  dropoff_lat double precision default null,
  dropoff_lng double precision default null,
  road_distance_km double precision default null
)
returns table (
  low_amount numeric,
  high_amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v public.vendors%rowtype;
  s public.app_settings%rowtype;
  z public.zones%rowtype;
  v_base_fare numeric;
  v_price_per_km numeric;
  straight_line_km double precision;
  distance_km double precision;
  cos_angle double precision;
  raw_amount numeric;
  v_high numeric;
  v_low numeric;
  resolved_zone_id uuid;
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

  raw_amount := v_base_fare + v_price_per_km * distance_km;
  v_high := least(raw_amount, 50);
  v_low := least(raw_amount * 0.85, v_high);

  return query select v_low, v_high, coalesce(s.currency, 'GHS');
end;
$$;

-- Same signature as 0031's version - only the body changes, so no
-- drop/grant needed.
create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null,
  road_distance_km double precision default null,
  scheduled_at timestamptz default null
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

  -- Prefer the zone the drop-off point actually falls in over the
  -- vendor's own registered zone - see the comment at the top of this
  -- file. Either can come back null, in which case this delivery simply
  -- has no zone, same as always.
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

  -- Pick whoever in the resolved zone is online, active, unfrozen, paid
  -- up on today's commission, and not already at the automatic-
  -- assignment cap - preferring whoever already has the most active
  -- deliveries in that same zone (consolidating a zone's requests onto
  -- one driver's route) short of the cap, tie-broken by lightest total
  -- workload for a fair bootstrap when nobody in the zone has any yet.
  -- Skipped entirely for a delivery scheduled well into the future - see
  -- 0030.
  if resolved_zone_id is not null and is_due_soon then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.zone_id = resolved_zone_id
      and public.driver_daily_fee_paid(p.id)
      and (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.zone_id = resolved_zone_id
          and d.status not in ('delivered', 'cancelled')
      ) < assign_cap
    order by
      (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.zone_id = resolved_zone_id
          and d.status not in ('delivered', 'cancelled')
      ) desc,
      (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.status not in ('delivered', 'cancelled')
      ) asc,
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
    customer_name, customer_phone,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    vendor_id, zone_id, created_by,
    assigned_driver_id, status, assigned_at,
    scheduled_at
  )
  values (
    customer_name, customer_phone,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, resolved_zone_id, null,
    target_driver_id, target_status, target_assigned_at,
    scheduled_at
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
