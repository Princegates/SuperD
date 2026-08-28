-- SuperD: three related additions to the customer/vendor experience
-- around an active delivery.
--
-- 1. A customer can optionally leave an email at request time
--    (`deliveries.customer_email`) so the driver-assigned notification
--    (see supabase/functions/notify-driver-assigned) can reach them by
--    email as well as SMS - still SMS-only if they don't. That
--    notification also now goes to the VENDOR (SMS to their phone, email
--    if they have one on file), and includes
--    `app_settings.support_phone` - a business support number for
--    reporting a problem with the delivery/driver - in every message.
--
-- 2. A vendor can see a live map of an active delivery from their own
--    orders page (get_vendor_deliveries now also returns the driver's
--    last known position and the drop-off point), instead of just a
--    status label.
--
-- 3. A customer can rate the driver (1-5 stars, optional comment) once a
--    delivery is marked delivered - `delivery_ratings`, one row per
--    delivery, submitted through submit_delivery_rating() and scoped to
--    the tracking code the customer already has, same as tracking the
--    order itself.

alter table public.deliveries
  add column if not exists customer_email text;

comment on column public.deliveries.customer_email is 'Optional - given at request time so the driver-assigned notification can also go by email, not just SMS. Null is fine; SMS still goes out either way.';

alter table public.app_settings
  add column if not exists support_phone text;

comment on column public.app_settings.support_phone is 'Business support/customer-service number, included in the driver-assigned SMS/email to the customer and vendor so they have a number to call about a problem with the delivery or driver.';

create table if not exists public.delivery_ratings (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null unique references public.deliveries (id) on delete cascade,
  driver_id uuid not null references public.profiles (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.delivery_ratings is 'A customer''s rating of the driver for one delivery - submitted (or edited) through submit_delivery_rating() only, scoped to their own tracking code. driver_id is captured at submission time so a driver''s average can be computed without joining back through deliveries.';

create index if not exists delivery_ratings_driver_idx on public.delivery_ratings (driver_id);

alter table public.delivery_ratings enable row level security;

drop policy if exists "delivery_ratings: dispatcher reads all" on public.delivery_ratings;
create policy "delivery_ratings: dispatcher reads all"
  on public.delivery_ratings for select
  using (public.is_dispatcher_or_above());

-- No insert/update policy for anyone - submit_delivery_rating() is the
-- only way in, same "SECURITY DEFINER function, no direct table access"
-- pattern as every other anonymous/public write in this app.

-- A customer rates (or re-rates, if they change their mind) the driver
-- on their own delivery, found by tracking code - never anyone else's.
-- Only allowed once the delivery is actually delivered, and only if a
-- driver was ever assigned to it.
create or replace function public.submit_delivery_rating(
  p_tracking_code text,
  p_rating integer,
  p_comment text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.deliveries%rowtype;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5.';
  end if;

  select * into d from public.deliveries where tracking_code = p_tracking_code;
  if not found then
    raise exception 'Delivery not found.';
  end if;
  if d.status <> 'delivered' then
    raise exception 'You can only rate a delivery once it has been delivered.';
  end if;
  if d.assigned_driver_id is null then
    raise exception 'This delivery has no driver to rate.';
  end if;

  insert into public.delivery_ratings (delivery_id, driver_id, rating, comment)
  values (
    d.id, d.assigned_driver_id, p_rating,
    nullif(trim(coalesce(p_comment, '')), '')
  )
  on conflict (delivery_id) do update
    set rating = excluded.rating,
        comment = excluded.comment,
        updated_at = now();
end;
$$;

grant execute on function public.submit_delivery_rating(text, integer, text) to anon, authenticated;

-- Adds customer_email - return type unchanged (still 3 columns), so no
-- drop needed, but the signature itself gains a trailing parameter,
-- which Postgres also disallows via plain create-or-replace - drop first.
drop function if exists public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision, timestamptz
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
    customer_name, customer_phone, customer_email,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    vendor_id, zone_id, created_by,
    assigned_driver_id, status, assigned_at,
    scheduled_at
  )
  values (
    customer_name, customer_phone, customer_email,
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

grant execute on function public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision, timestamptz, text
) to anon, authenticated;

-- Adds the assigned driver's live position and the drop-off point, so a
-- vendor can optionally see a map of an active delivery instead of just
-- its status - return shape changes, drop first.
drop function if exists public.get_vendor_deliveries(text);

create or replace function public.get_vendor_deliveries(p_orders_code text)
returns table (
  id uuid,
  tracking_code text,
  status public.delivery_status,
  customer_name text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  driver_name text,
  driver_phone text,
  driver_lat double precision,
  driver_lng double precision,
  driver_location_updated_at timestamptz,
  created_at timestamptz,
  scheduled_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    d.dropoff_lat, d.dropoff_lng,
    p.full_name as driver_name, p.phone as driver_phone,
    p.last_lat as driver_lat, p.last_lng as driver_lng,
    p.location_updated_at as driver_location_updated_at,
    d.created_at, d.scheduled_at
  from public.deliveries d
  join public.vendors v on v.id = d.vendor_id
  left join public.profiles p on p.id = d.assigned_driver_id
  where v.orders_code = p_orders_code
  order by d.created_at desc;
$$;

grant execute on function public.get_vendor_deliveries(text) to anon, authenticated;

-- Adds whether (and how) the customer already rated this delivery, so
-- the tracking page can show/edit an existing rating instead of always
-- presenting a blank form - return shape changes, drop first.
drop function if exists public.get_delivery_by_tracking_code(text);

create or replace function public.get_delivery_by_tracking_code(p_tracking_code text)
returns table (
  id uuid,
  tracking_code text,
  status public.delivery_status,
  customer_name text,
  dropoff_address text,
  driver_name text,
  driver_phone text,
  created_at timestamptz,
  scheduled_at timestamptz,
  rating integer,
  rating_comment text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    p.full_name as driver_name, p.phone as driver_phone,
    d.created_at, d.scheduled_at,
    r.rating, r.comment as rating_comment
  from public.deliveries d
  left join public.profiles p on p.id = d.assigned_driver_id
  left join public.delivery_ratings r on r.delivery_id = d.id
  where d.tracking_code = p_tracking_code;
$$;

grant execute on function public.get_delivery_by_tracking_code(text) to anon, authenticated;
