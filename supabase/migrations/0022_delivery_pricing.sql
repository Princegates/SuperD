-- SuperD: automatic delivery pricing for customer-submitted requests.
--
-- Customer Delivery Price = Base Delivery Fare + Distance Charge
-- (+ optional extras, added later by a dispatcher if needed - see
-- payments.notes/amount, which a dispatcher can already adjust by hand).
--
-- Both the base fare and per-km rate are super-admin-configurable, live
-- in `app_settings` right alongside currency/theme. Distance is a plain
-- great-circle (haversine) calculation between the vendor's registered
-- location and the customer's dropped pin - no paid Distance Matrix API
-- needed, consistent with how this app already avoids Google Places for
-- address search. It's a straight-line distance, not real road distance,
-- so treat it as a reasonable estimate, not a precise fare meter.

alter table public.app_settings
  add column if not exists base_fare numeric(10, 2) not null default 5,
  add column if not exists price_per_km numeric(10, 2) not null default 1.5;

-- Anonymous customers can't read app_settings directly (its RLS requires
-- auth.uid()), so this exposes just the three pricing-relevant fields -
-- same "narrow SECURITY DEFINER function, not direct table access"
-- pattern as get_vendor_by_code and friends below.
create or replace function public.get_pricing_config()
returns table (
  base_fare numeric,
  price_per_km numeric,
  currency text
)
language sql
security definer
set search_path = public
stable
as $$
  select base_fare, price_per_km, currency from public.app_settings limit 1;
$$;

grant execute on function public.get_pricing_config() to anon, authenticated;

-- submit_delivery_request's return type is changing (tracking code plus
-- the quoted price), so the old single-text-returning version needs
-- dropping first - a plain `create or replace` can't change a function's
-- return type.
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
  new_tracking_code text;
  distance_km double precision;
  amount numeric(10, 2);
  cos_angle double precision;
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;

  -- Distance-based pricing needs both ends of the trip pinned - a
  -- customer who only typed a text address without dropping a pin gets
  -- just the base fare instead, rather than blocking submission.
  if dropoff_lat is not null and dropoff_lng is not null
     and v.location_lat is not null and v.location_lng is not null then
    cos_angle := sin(radians(v.location_lat)) * sin(radians(dropoff_lat))
      + cos(radians(v.location_lat)) * cos(radians(dropoff_lat))
        * cos(radians(dropoff_lng) - radians(v.location_lng));
    -- Clamp before acos() - floating point rounding can push an
    -- identical-point angle a hair past 1.0, which acos() rejects.
    distance_km := 6371 * acos(least(1.0, greatest(-1.0, cos_angle)));
  else
    distance_km := 0;
  end if;

  amount := coalesce(s.base_fare, 0) + coalesce(s.price_per_km, 0) * distance_km;

  insert into public.deliveries (
    customer_name, customer_phone,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    vendor_id, zone_id, created_by
  )
  values (
    customer_name, customer_phone,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, v.zone_id, null
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
  text, text, text, text, double precision, double precision, text
) to anon, authenticated;
