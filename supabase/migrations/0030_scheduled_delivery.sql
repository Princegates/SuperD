-- SuperD: lets a customer (or a dispatcher creating one by hand) pick a
-- future date/time for a delivery instead of always meaning "right now".
-- `scheduled_at` null keeps today's behavior exactly as-is (ASAP).
--
-- A scheduled request skips automatic same-zone driver assignment (see
-- 0026/0028's submit_delivery_request) when it's for later than 15
-- minutes from now - there's no point handing it to whichever driver
-- happens to be online at submission time when the job isn't ready to
-- start yet. It sits at `pending` until a dispatcher assigns it (the
-- animated reminder on the admin dashboard - see
-- console/screens or admin_dashboard_screen.dart - is what prompts them
-- to do that as the scheduled time gets close). Once scheduled_at is
-- within that 15-minute window (or null, i.e. ASAP), auto-assignment
-- behaves exactly as before.

alter table public.deliveries
  add column if not exists scheduled_at timestamptz;

comment on column public.deliveries.scheduled_at is 'When the customer wants this delivered - null means as soon as possible (the historical default).';

drop function if exists public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision
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
  target_driver_id uuid;
  target_status public.delivery_status;
  target_assigned_at timestamptz;
  is_due_soon boolean;
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

  is_due_soon := scheduled_at is null or scheduled_at <= now() + interval '15 minutes';

  -- Pick whoever in the vendor's zone is online, active, and unfrozen -
  -- preferring whoever already has the most active deliveries in that
  -- same zone (consolidating a zone's requests onto one driver's route),
  -- tie-broken by lightest total workload for a fair bootstrap when
  -- nobody in the zone has any yet. Skipped entirely for a delivery
  -- scheduled well into the future - see comment at the top of this file.
  if v.zone_id is not null and is_due_soon then
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
    assigned_driver_id, status, assigned_at,
    scheduled_at
  )
  values (
    customer_name, customer_phone,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, v.zone_id, null,
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
  text, text, text, text, double precision, double precision, text, double precision, timestamptz
) to anon, authenticated;

-- Both customer/vendor-facing read functions also start returning
-- scheduled_at, so a vendor's order list and a customer's own tracking
-- page can show it (return type changes, so drop first).

drop function if exists public.get_vendor_deliveries(text);

create or replace function public.get_vendor_deliveries(p_orders_code text)
returns table (
  id uuid,
  tracking_code text,
  status public.delivery_status,
  customer_name text,
  dropoff_address text,
  driver_name text,
  driver_phone text,
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
    p.full_name as driver_name, p.phone as driver_phone, d.created_at,
    d.scheduled_at
  from public.deliveries d
  join public.vendors v on v.id = d.vendor_id
  left join public.profiles p on p.id = d.assigned_driver_id
  where v.orders_code = p_orders_code
  order by d.created_at desc;
$$;

grant execute on function public.get_vendor_deliveries(text) to anon, authenticated;

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
  scheduled_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    p.full_name as driver_name, p.phone as driver_phone, d.created_at,
    d.scheduled_at
  from public.deliveries d
  left join public.profiles p on p.id = d.assigned_driver_id
  where d.tracking_code = p_tracking_code;
$$;

grant execute on function public.get_delivery_by_tracking_code(text) to anon, authenticated;
