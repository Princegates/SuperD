-- SuperD: closes the gap 0058_public_form_rate_limiting.sql's throttle
-- deliberately left open - a determined attacker rotating phone number
-- and IP per request sails right past a rate limit. This routes the two
-- public no-login forms through a Cloudflare Turnstile CAPTCHA instead
-- of letting anon call submit_delivery_request()/register_vendor()
-- directly:
--
--   1. anon's execute grant on both functions is revoked here -
--      `authenticated` keeps theirs (a signed-in dispatcher/admin testing
--      a vendor's public link isn't the anonymous-bot threat this
--      guards against, and CAPTCHA has no real security value for a
--      traceable, already-logged-in caller).
--   2. Two new Edge Functions (public-submit-delivery-request,
--      public-register-vendor) become the only way in for anonymous
--      traffic - service-role, so they can still call these functions
--      after the revoke above. Each verifies a Turnstile token with
--      Cloudflare before doing anything else - see the README's "Public
--      form protection" section for the remaining setup and
--      _shared/turnstile.ts for the verification call itself.
--   3. Both functions gain a trailing p_client_ip param (same
--      add-a-default-arg-at-the-end pattern 0034/0042/0051 already used
--      to grow these signatures without a drop) - the Edge Functions
--      pass the caller's real IP through explicitly for
--      enforce_rate_limit()'s per-IP check, since request_ip() alone
--      would otherwise see the Edge Function's own request to
--      PostgREST, not the original browser's.
--
-- A project that hasn't set TURNSTILE_SECRET_KEY yet is unaffected
-- end-to-end: verifyTurnstileToken() no-ops without it, so these two
-- functions behave exactly as before - only the entry point (an Edge
-- Function instead of a direct RPC call) changed.

revoke execute on function public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision, timestamptz, text, uuid
) from anon;

revoke execute on function public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid
) from anon;

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

grant execute on function public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision, timestamptz, text, uuid, text
) to authenticated;

create or replace function public.register_vendor(
  vendor_name text,
  zone_id uuid,
  location_lat double precision,
  location_lng double precision,
  phone text,
  email text default null,
  created_by uuid default null,
  p_client_ip text default null
)
returns table (
  code text,
  orders_code text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  new_orders_code text;
begin
  perform public.enforce_rate_limit(
    'phone:' || phone, 'register_vendor', 3, interval '1 day'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'register_vendor', 10, interval '1 day'
  );

  loop
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    new_orders_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    begin
      insert into public.vendors (
        code, orders_code, vendor_name, zone_id, location_lat, location_lng,
        phone, email, created_by
      )
      values (
        new_code, new_orders_code, vendor_name, zone_id, location_lat,
        location_lng, phone, email, created_by
      );
      exit;
    exception when unique_violation then
      -- Vanishingly unlikely with 10/12-character codes - just try again.
    end;
  end loop;
  return query select new_code, new_orders_code;
end;
$$;

grant execute on function public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid, text
) to authenticated;
