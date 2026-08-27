-- SuperD: separates a vendor's PUBLIC link (given to every customer, to
-- place orders) from a PRIVATE "view all my orders" link. Previously the
-- exact same code did both jobs - get_vendor_deliveries() was keyed by the
-- same `code` printed on the customer-facing request form - so any
-- customer who received a vendor's ordering link could also open
-- <link>/orders and see every OTHER customer's name, phone, drop-off
-- address, and assigned driver's phone number for that vendor. That's the
-- privacy bug this migration closes.
--
-- vendors.orders_code is a second, separate secret, generated alongside
-- `code` at registration and never returned by any customer-facing
-- function (get_vendor_by_code, submit_delivery_request still only ever
-- hand back `code`/tracking_code). Only the vendor themselves receives
-- orders_code, once, at registration time - dispatchers/super admins can
-- also see it via the Vendors screen (already RLS-gated to them).
--
-- A customer's own "track my order" page moves to a new
-- get_delivery_by_tracking_code() function instead, scoped to the one
-- delivery whose tracking_code they were given when they submitted it -
-- never the vendor's full order list.

alter table public.vendors
  add column if not exists orders_code text;

update public.vendors
set orders_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
where orders_code is null;

alter table public.vendors
  alter column orders_code set not null;

alter table public.vendors
  drop constraint if exists vendors_orders_code_key,
  add constraint vendors_orders_code_key unique (orders_code);

comment on column public.vendors.orders_code is 'A SEPARATE secret from the public `code` (which every customer receives to place an order) - used only for the vendor''s own "view all my orders" page. Never expose this via get_vendor_by_code, submit_delivery_request, or any other customer-facing function.';

-- register_vendor now returns both codes - the return type is changing
-- (text -> a two-column table), so the old overload needs dropping first.
drop function if exists public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid
);

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
  text, uuid, double precision, double precision, text, text, uuid
) to anon, authenticated;

-- The actual fix: get_vendor_deliveries is now keyed by the private
-- orders_code, not the public code every customer already has.
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
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    p.full_name as driver_name, p.phone as driver_phone, d.created_at
  from public.deliveries d
  join public.vendors v on v.id = d.vendor_id
  left join public.profiles p on p.id = d.assigned_driver_id
  where v.orders_code = p_orders_code
  order by d.created_at desc;
$$;

grant execute on function public.get_vendor_deliveries(text) to anon, authenticated;

-- A customer's own single-order tracking, scoped to the tracking_code
-- they were given at submission - never returns anything about any other
-- delivery, even another one from the same vendor.
create or replace function public.get_delivery_by_tracking_code(p_tracking_code text)
returns table (
  id uuid,
  tracking_code text,
  status public.delivery_status,
  customer_name text,
  dropoff_address text,
  driver_name text,
  driver_phone text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    p.full_name as driver_name, p.phone as driver_phone, d.created_at
  from public.deliveries d
  left join public.profiles p on p.id = d.assigned_driver_id
  where d.tracking_code = p_tracking_code;
$$;

grant execute on function public.get_delivery_by_tracking_code(text) to anon, authenticated;
