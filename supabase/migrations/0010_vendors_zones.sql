-- SuperD: vendors, zones, and public (no-login) delivery requests.
--
-- Zones: a fixed, admin-managed list used to group drivers and vendors -
-- mainly so a dispatcher assigning a driver can see who's actually nearby,
-- and so pricing can eventually vary by zone.
--
-- Vendors: a business gets a unique code (their link, e.g. /v/ABCD123456)
-- that they share with their own customers. A customer opens it, fills in
-- their own delivery details with no SuperD account needed, and it lands
-- as a pending delivery for a dispatcher to assign a driver to. The same
-- code doubles as the vendor's own order-tracking link.
--
-- All of this public/no-login access goes through SECURITY DEFINER
-- functions below, never direct table grants - each function only ever
-- returns/touches the one vendor matched by the code it's given, so
-- there's no way to enumerate other vendors' data through it.

create table if not exists public.zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists zone_id uuid references public.zones (id);

create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  vendor_name text not null,
  zone_id uuid references public.zones (id),
  location_lat double precision,
  location_lng double precision,
  phone text not null,
  is_active boolean not null default true,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.deliveries
  add column if not exists vendor_id uuid references public.vendors (id),
  add column if not exists zone_id uuid references public.zones (id);

-- A vendor-submitted request has no dispatcher/super admin author.
alter table public.deliveries
  alter column created_by drop not null;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.zones enable row level security;
alter table public.vendors enable row level security;

-- Zones are just names - safe for anyone to read (drivers/vendor forms need
-- the list), but only a super admin can add/change/remove one, since zones
-- double as pricing tiers.
drop policy if exists "zones: anyone reads" on public.zones;
create policy "zones: anyone reads"
  on public.zones for select
  using (true);

drop policy if exists "zones: super admin inserts" on public.zones;
create policy "zones: super admin inserts"
  on public.zones for insert
  with check (public.is_super_admin());

drop policy if exists "zones: super admin updates" on public.zones;
create policy "zones: super admin updates"
  on public.zones for update
  using (public.is_super_admin())
  with check (public.is_super_admin());

drop policy if exists "zones: super admin deletes" on public.zones;
create policy "zones: super admin deletes"
  on public.zones for delete
  using (public.is_super_admin());

-- Vendors are managed like drivers - a dispatcher or super admin has full
-- access. There is deliberately no anon policy here at all: the public
-- signup/order forms never touch this table directly, only through the
-- functions below.
drop policy if exists "vendors: dispatcher manages" on public.vendors;
create policy "vendors: dispatcher manages"
  on public.vendors for all
  using (public.is_dispatcher_or_above())
  with check (public.is_dispatcher_or_above());

-- ---------------------------------------------------------------------------
-- Public-facing functions (callable by the anon key, no session required)
-- ---------------------------------------------------------------------------

-- Registers a vendor and returns their unique code. Used both by the
-- public self-service signup form (created_by left null) and by the
-- dispatcher/super-admin "Add vendor" screen (passes their own id) - same
-- code-generation logic either way, so there's only one place it lives.
create or replace function public.register_vendor(
  vendor_name text,
  zone_id uuid,
  location_lat double precision,
  location_lng double precision,
  phone text,
  created_by uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
begin
  loop
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.vendors (
        code, vendor_name, zone_id, location_lat, location_lng, phone, created_by
      )
      values (
        new_code, vendor_name, zone_id, location_lat, location_lng, phone, created_by
      );
      exit;
    exception when unique_violation then
      -- Vanishingly unlikely with a 10-character code - just try again.
    end;
  end loop;
  return new_code;
end;
$$;

grant execute on function public.register_vendor(
  text, uuid, double precision, double precision, text, uuid
) to anon, authenticated;

-- Looks up a vendor by their public code - used to show "Ordering from
-- {vendor_name}" on the customer request form before it's filled in.
create or replace function public.get_vendor_by_code(p_code text)
returns table (
  id uuid,
  vendor_name text,
  zone_name text,
  location_lat double precision,
  location_lng double precision,
  is_active boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select v.id, v.vendor_name, z.name as zone_name, v.location_lat, v.location_lng, v.is_active
  from public.vendors v
  left join public.zones z on z.id = v.zone_id
  where v.code = p_code;
$$;

grant execute on function public.get_vendor_by_code(text) to anon, authenticated;

-- Creates a pending delivery on behalf of a customer who opened a vendor's
-- link - no login, no dispatcher involved yet. Pickup is always the
-- vendor's own registered location; the customer only supplies drop-off.
create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vendors%rowtype;
  new_tracking_code text;
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

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
  returning tracking_code into new_tracking_code;

  return new_tracking_code;
end;
$$;

grant execute on function public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text
) to anon, authenticated;

-- Every delivery ever placed through a given vendor's link - this is what
-- powers the vendor's own order-tracking page (same code as their link).
create or replace function public.get_vendor_deliveries(p_code text)
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
  where v.code = p_code
  order by d.created_at desc;
$$;

grant execute on function public.get_vendor_deliveries(text) to anon, authenticated;
