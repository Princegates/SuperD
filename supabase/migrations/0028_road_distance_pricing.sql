-- SuperD: prices a delivery by real road distance (from Google's
-- Directions API, via the get-road-distance Edge Function) instead of
-- only the straight-line haversine calculation, when the app was able to
-- fetch one.
--
-- The client (customer_request_screen.dart) fetches the road distance
-- itself and passes it in as road_distance_km - but the actual number
-- used is never LESS than the straight-line distance computed here
-- server-side, since that's a physical impossibility for any real route
-- (the shortest path between two points is always a straight line). That
-- floor means a customer can't under-report distance to pay less by
-- passing a bogus small number - the worst they can do is fall back to
-- exactly what pricing already was before this migration.
--
-- If road_distance_km is null (Directions API call failed, or the
-- customer's browser/app couldn't reach it), this behaves exactly as
-- before - pure straight-line pricing.

drop function if exists public.get_delivery_price_estimate(
  text, double precision, double precision
);

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
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;
  if v.zone_id is not null then
    select * into z from public.zones where id = v.zone_id;
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

grant execute on function public.get_delivery_price_estimate(
  text, double precision, double precision, double precision
) to anon, authenticated;

drop function if exists public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text
);

create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null,
  road_distance_km double precision default null
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
  target_driver_id uuid;
  target_status public.delivery_status;
  target_assigned_at timestamptz;
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;
  if v.zone_id is not null then
    select * into z from public.zones where id = v.zone_id;
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

  -- Pick whoever in the vendor's zone is online, active, and unfrozen -
  -- preferring whoever already has the most active deliveries in that
  -- same zone (consolidating a zone's requests onto one driver's route),
  -- tie-broken by lightest total workload for a fair bootstrap when
  -- nobody in the zone has any yet.
  if v.zone_id is not null then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.zone_id = v.zone_id
    order by
      (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.zone_id = v.zone_id
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
    assigned_driver_id, status, assigned_at
  )
  values (
    customer_name, customer_phone,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, v.zone_id, null,
    target_driver_id, target_status, target_assigned_at
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

grant execute on function public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision
) to anon, authenticated;
