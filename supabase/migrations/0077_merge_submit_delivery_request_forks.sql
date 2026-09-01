-- Fixes submit_delivery_request() having silently forked into two live,
-- diverging overloads - the same root cause as
-- 0076_drop_stale_register_vendor_overload.sql (0059_public_form_captcha_gate.sql
-- added a trailing p_client_ip parameter via `create or replace function`
-- without dropping the old signature first, which doesn't error - it just
-- creates a second, separate overload). Unlike register_vendor, this one
-- never surfaced as an outright ambiguous-call error, because the only
-- caller (public-submit-delivery-request, since anon's direct grant was
-- revoked in that same migration) always passes p_client_ip explicitly,
-- so PostgREST could always resolve to the 12-argument overload without
-- an issue there.
--
-- The real damage: 0065_delivery_vehicle_type.sql and
-- 0067_daily_commission_settlement.sql both edited the OLD 11-argument
-- overload (missing p_client_ip) instead of the 12-argument one actually
-- being called - each `create or replace` matched that older signature
-- exactly, so it kept editing that dead branch instead of erroring. That
-- means every public delivery request submitted since 0067 merged has
-- been running the 12-argument branch, which is missing BOTH of those
-- migrations' real functional changes:
--   1. `driver_has_overdue_commission()` was never added to the driver-
--      eligibility checks here (both auto-assignment tiers) - see
--      0067's OWN assign_pending_deliveries_near_driver(), which
--      correctly combines it with driver_under_in_transit_limit()
--      together, proving both were meant to gate together. A driver who
--      owes commission could still have been auto-assigned a new public
--      delivery request this whole time.
--   2. `vehicle_type_id` was never persisted onto the new deliveries row
--      (p_vehicle_type_id was still used to compute the fare correctly,
--      just never saved) - so a request's chosen vehicle type has been
--      silently lost since 0065, even though pricing for it was correct.
--
-- This migration drops the stale 11-argument overload and replaces the
-- 12-argument one with a single, complete, merged body: 0062's structure
-- (rate limiting, driver_under_in_transit_limit) plus the two pieces of
-- 0065/0067 that never made it in.
drop function if exists public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text,
  double precision, timestamptz, text, uuid
);

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
  p_vehicle_type_id uuid default null,
  p_client_ip text default null
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
  perform public.enforce_rate_limit(
    'phone:' || customer_phone, 'submit_delivery_request', 5, interval '10 minutes'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'submit_delivery_request', 20, interval '10 minutes'
  );

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
      and not public.driver_has_overdue_commission(p.id)
      and public.driver_under_in_transit_limit(p.id)
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
        and not public.driver_has_overdue_commission(p.id)
        and public.driver_under_in_transit_limit(p.id)
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
    scheduled_at, auto_assigned, vehicle_type_id
  )
  values (
    customer_name, customer_phone, customer_email,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, resolved_zone_id, null,
    target_driver_id, target_status, target_assigned_at,
    scheduled_at, target_driver_id is not null, p_vehicle_type_id
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
  text, text, text, text, double precision, double precision, text,
  double precision, timestamptz, text, uuid, text
) to authenticated;
