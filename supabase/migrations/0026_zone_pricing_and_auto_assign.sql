-- SuperD: zone-aware pricing (with a low-high estimate capped at 50 that a
-- customer sees the moment they set a drop-off, before submitting), plus
-- automatic same-zone driver assignment - both happen inside
-- submit_delivery_request, so a customer-submitted request needs no
-- dispatcher at all unless nobody's available.
--
-- Pricing: a vendor's zone can set its own base_fare/price_per_km,
-- overriding the app-wide default from app_settings (0022_delivery_pricing.sql).
-- Leave a zone's rates blank to keep using the global default.
--
-- Range + cap: every quote (the pre-submit estimate AND the actual charged
-- amount) is capped at 50 in the app's currency - this business doesn't
-- charge more than that for a single delivery, however far the drop-off.
-- The pre-submit estimate is a range (roughly 15% below the capped amount
-- up to it) rather than one number, since a straight-line distance to a
-- pin the customer just dropped is necessarily an estimate.
--
-- Auto-assignment: when a vendor's zone has an online, active, unfrozen
-- driver, submit_delivery_request assigns them immediately (no dispatcher
-- needed) - and specifically prefers whoever in that zone ALREADY has the
-- most active same-zone deliveries, so multiple requests from the same
-- area consolidate onto one driver's route instead of spreading thin.
-- Ties (nobody yet has any) go to whoever currently has the lightest
-- total workload. A dispatcher can always reassign it by hand afterward,
-- same as any other delivery - this is just what happens automatically
-- when nobody has to.

alter table public.zones
  add column if not exists base_fare numeric(10, 2),
  add column if not exists price_per_km numeric(10, 2);

comment on column public.zones.base_fare is 'Overrides app_settings.base_fare for vendors in this zone. Null = use the app-wide default.';
comment on column public.zones.price_per_km is 'Overrides app_settings.price_per_km for vendors in this zone. Null = use the app-wide default.';

-- Superseded by get_delivery_price_estimate() below, which is zone-aware
-- and returns a range - nothing else in the app calls this any more.
drop function if exists public.get_pricing_config();

create or replace function public.get_delivery_price_estimate(
  p_code text,
  dropoff_lat double precision default null,
  dropoff_lng double precision default null
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
    distance_km := 6371 * acos(least(1.0, greatest(-1.0, cos_angle)));
  else
    distance_km := 0;
  end if;

  raw_amount := v_base_fare + v_price_per_km * distance_km;
  v_high := least(raw_amount, 50);
  v_low := least(raw_amount * 0.85, v_high);

  return query select v_low, v_high, coalesce(s.currency, 'GHS');
end;
$$;

grant execute on function public.get_delivery_price_estimate(text, double precision, double precision) to anon, authenticated;

-- Same signature/return shape as 0022_delivery_pricing.sql - now
-- zone-aware, capped at 50 (matching get_delivery_price_estimate()'s high
-- end so what a customer was quoted and what they're actually charged
-- never disagree), and auto-assigns a driver when one is available.
create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null
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
    distance_km := 6371 * acos(least(1.0, greatest(-1.0, cos_angle)));
  else
    distance_km := 0;
  end if;

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
