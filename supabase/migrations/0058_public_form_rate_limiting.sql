-- SuperD: the two public, no-login forms - a customer submitting a
-- delivery request via a vendor's link (submit_delivery_request()) and a
-- vendor self-signing up (register_vendor()) - are callable by anyone,
-- any number of times, with no limit at all. This adds a basic per-phone
-- and per-IP throttle to both, so a script can't flood either one -
-- spamming the dispatcher queue, burning through the Twilio/Resend
-- notification budget (every request sends at least one message), or
-- filling the Vendors list with junk.
--
-- This is a deliberately simple, self-contained first layer - it stops
-- naive/sloppy scripted abuse with no new infrastructure. It does NOT
-- stop a determined attacker rotating both phone number and IP per
-- request; closing that gap needs a real CAPTCHA (Cloudflare Turnstile),
-- which - because Postgres can't make the synchronous "verify this token
-- with Cloudflare" call a CAPTCHA needs - has to live in front of these
-- functions as an Edge Function, not in this migration. See the README's
-- "Public form protection" section once that lands.

create table if not exists public.rate_limit_hits (
  id uuid primary key default gen_random_uuid(),
  key text not null,
  action text not null,
  created_at timestamptz not null default now()
);

comment on table public.rate_limit_hits is 'One row per allowed call to a throttled public function (see enforce_rate_limit()) - keyed by a caller identifier (phone/IP) and the action name. No RLS policies for anon/authenticated on purpose: only enforce_rate_limit() (SECURITY DEFINER) ever touches this table.';

create index if not exists rate_limit_hits_key_action_created_idx
  on public.rate_limit_hits (key, action, created_at);

alter table public.rate_limit_hits enable row level security;

-- Best-effort caller IP from whatever PostgREST forwarded - Supabase
-- Cloud sets this up out of the box; a self-hosted project may need its
-- Kong/proxy config checked to confirm x-forwarded-for actually reaches
-- PostgREST. Never raises - a project where this isn't available just
-- falls back to phone-only throttling instead of failing every request.
create or replace function public.request_ip()
returns text
language plpgsql
stable
as $$
declare
  headers json;
  xff text;
begin
  begin
    headers := current_setting('request.headers', true)::json;
  exception when others then
    return null;
  end;

  if headers is null then
    return null;
  end if;

  xff := headers ->> 'x-forwarded-for';
  if xff is null or trim(xff) = '' then
    return null;
  end if;

  -- x-forwarded-for can be "client, proxy1, proxy2, ..." - the first
  -- entry is the original caller.
  return trim(split_part(xff, ',', 1));
end;
$$;

-- Raises if [p_key] has already made [p_max_count] or more calls tagged
-- [p_action] within the last [p_window] - otherwise records this call and
-- returns normally. A no-op when [p_key] is null (e.g. request_ip()
-- couldn't determine one) rather than blocking everyone alike.
--
-- Counts existing hits BEFORE inserting a new one, and only inserts when
-- allowed - a blocked call is never logged. That's deliberate, not a
-- missed edge case: raising an exception here aborts the whole calling
-- transaction (including anything inserted earlier in it), so a hit
-- logged right before raising would just roll back anyway. The already-
-- logged hits from earlier, still-allowed calls are exactly what keeps a
-- caller blocked for the rest of the window regardless.
--
-- Opportunistically prunes hits older than a day on roughly 1% of calls,
-- so this table doesn't grow forever without needing a scheduled job.
create or replace function public.enforce_rate_limit(
  p_key text,
  p_action text,
  p_max_count integer,
  p_window interval
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_count integer;
begin
  if p_key is null then
    return;
  end if;

  if random() < 0.01 then
    delete from public.rate_limit_hits where created_at < now() - interval '1 day';
  end if;

  select count(*) into recent_count
  from public.rate_limit_hits
  where key = p_key
    and action = p_action
    and created_at > now() - p_window;

  if recent_count >= p_max_count then
    raise exception 'Too many requests - please wait a few minutes and try again.';
  end if;

  insert into public.rate_limit_hits (key, action) values (p_key, p_action);
end;
$$;

-- Same signature as 0052_high_performer_assignment_fallback.sql's version
-- - only the two enforce_rate_limit() calls at the top are new.
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
  perform public.enforce_rate_limit(
    'phone:' || customer_phone, 'submit_delivery_request', 5, interval '10 minutes'
  );
  perform public.enforce_rate_limit(
    'ip:' || public.request_ip(), 'submit_delivery_request', 20, interval '10 minutes'
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

-- Same signature as 0027_separate_vendor_orders_code.sql's version - only
-- the two enforce_rate_limit() calls at the top are new. Phone/IP limits
-- are tighter and cover a longer window than the delivery-request ones
-- above: signing up as a vendor is a rarer, higher-stakes action than
-- placing one order, so there's less legitimate reason to do it
-- repeatedly in a short span.
create or replace function public.register_vendor(
  vendor_name text,
  zone_id uuid,
  location_lat double precision,
  location_lng double precision,
  phone text,
  email text default null,
  created_by uuid default null
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
    'ip:' || public.request_ip(), 'register_vendor', 10, interval '1 day'
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
