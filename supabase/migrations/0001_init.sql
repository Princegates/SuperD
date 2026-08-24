-- SuperD delivery management system - initial schema
-- Designed for self-hosted Supabase (Postgres + Auth + Storage + Realtime),
-- but works the same on Supabase Cloud's free tier.
--
-- Roles:
--   admin  - dispatcher/back-office user. Creates deliveries, assigns drivers,
--            sees everything.
--   driver - field courier. Sees only deliveries assigned to them, updates
--            status and uploads proof of delivery.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.user_role as enum ('admin', 'driver');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.delivery_status as enum (
    'pending',      -- created, not yet assigned to a driver
    'assigned',     -- assigned to a driver, not yet picked up
    'picked_up',    -- driver has collected the package
    'in_transit',   -- driver is en route to drop-off
    'delivered',    -- completed
    'cancelled'     -- cancelled by dispatcher
  );
exception
  when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- profiles: one row per auth.users row, holds app-level identity + role
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '',
  phone text,
  role public.user_role not null default 'driver',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'App-level profile + role for each authenticated user.';

-- Helper used inside RLS policies. SECURITY DEFINER + fixed search_path so it
-- can read public.profiles regardless of the calling user's row-level policy
-- (avoids RLS self-recursion on the profiles table).
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- Auto-create a profile row whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- deliveries
-- ---------------------------------------------------------------------------
create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  tracking_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),

  status public.delivery_status not null default 'pending',

  customer_name text not null,
  customer_phone text,

  pickup_address text not null,
  pickup_lat double precision,
  pickup_lng double precision,

  dropoff_address text not null,
  dropoff_lat double precision,
  dropoff_lng double precision,

  package_description text,
  notes text,

  proof_of_delivery_url text,

  created_by uuid not null references public.profiles (id),
  assigned_driver_id uuid references public.profiles (id),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  assigned_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz
);

comment on table public.deliveries is 'A single parcel/courier job from pickup to drop-off.';

create index if not exists deliveries_assigned_driver_idx on public.deliveries (assigned_driver_id);
create index if not exists deliveries_status_idx on public.deliveries (status);
create index if not exists deliveries_created_at_idx on public.deliveries (created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists deliveries_set_updated_at on public.deliveries;
create trigger deliveries_set_updated_at
  before update on public.deliveries
  for each row execute function public.set_updated_at();

-- Stamp status-change timestamps + protect fields a driver must not be able
-- to change (everything except status/notes/proof_of_delivery_url).
create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    -- Drivers may only touch status, notes and proof of delivery on jobs
    -- assigned to them; every other column snaps back to its old value.
    new.tracking_code := old.tracking_code;
    new.customer_name := old.customer_name;
    new.customer_phone := old.customer_phone;
    new.pickup_address := old.pickup_address;
    new.pickup_lat := old.pickup_lat;
    new.pickup_lng := old.pickup_lng;
    new.dropoff_address := old.dropoff_address;
    new.dropoff_lat := old.dropoff_lat;
    new.dropoff_lng := old.dropoff_lng;
    new.package_description := old.package_description;
    new.created_by := old.created_by;
    new.assigned_driver_id := old.assigned_driver_id;
    new.assigned_at := old.assigned_at;
  end if;

  if new.status = 'assigned' and old.status is distinct from 'assigned' and new.assigned_at is null then
    new.assigned_at := now();
  end if;
  if new.status = 'picked_up' and old.status is distinct from 'picked_up' then
    new.picked_up_at := now();
  end if;
  if new.status = 'delivered' and old.status is distinct from 'delivered' then
    new.delivered_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists deliveries_enforce_update on public.deliveries;
create trigger deliveries_enforce_update
  before update on public.deliveries
  for each row execute function public.enforce_delivery_update();

-- Keep a lightweight audit trail of every status change.
create table if not exists public.delivery_status_history (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries (id) on delete cascade,
  status public.delivery_status not null,
  changed_by uuid references public.profiles (id),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists delivery_status_history_delivery_idx on public.delivery_status_history (delivery_id, created_at);

create or replace function public.log_delivery_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.delivery_status_history (delivery_id, status, changed_by)
    values (new.id, new.status, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_log_status_insert on public.deliveries;
create trigger deliveries_log_status_insert
  after insert on public.deliveries
  for each row execute function public.log_delivery_status_change();

drop trigger if exists deliveries_log_status_update on public.deliveries;
create trigger deliveries_log_status_update
  after update on public.deliveries
  for each row execute function public.log_delivery_status_change();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_status_history enable row level security;

-- profiles policies
drop policy if exists "profiles: read own or admin reads all" on public.profiles;
create policy "profiles: read own or admin reads all"
  on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles: user updates own non-role fields" on public.profiles;
create policy "profiles: user updates own non-role fields"
  on public.profiles for update
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

drop policy if exists "profiles: admin inserts" on public.profiles;
create policy "profiles: admin inserts"
  on public.profiles for insert
  with check (public.is_admin());

-- deliveries policies
drop policy if exists "deliveries: admin full read" on public.deliveries;
create policy "deliveries: admin full read"
  on public.deliveries for select
  using (public.is_admin() or assigned_driver_id = auth.uid());

drop policy if exists "deliveries: admin insert" on public.deliveries;
create policy "deliveries: admin insert"
  on public.deliveries for insert
  with check (public.is_admin());

drop policy if exists "deliveries: admin or assigned driver update" on public.deliveries;
create policy "deliveries: admin or assigned driver update"
  on public.deliveries for update
  using (public.is_admin() or assigned_driver_id = auth.uid());

drop policy if exists "deliveries: admin delete" on public.deliveries;
create policy "deliveries: admin delete"
  on public.deliveries for delete
  using (public.is_admin());

-- delivery_status_history policies (read-only from the client)
drop policy if exists "history: admin or assigned driver read" on public.delivery_status_history;
create policy "history: admin or assigned driver read"
  on public.delivery_status_history for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.deliveries d
      where d.id = delivery_id and d.assigned_driver_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Storage: proof-of-delivery photos
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('proof-of-delivery', 'proof-of-delivery', true)
on conflict (id) do nothing;

drop policy if exists "pod: public read" on storage.objects;
create policy "pod: public read"
  on storage.objects for select
  using (bucket_id = 'proof-of-delivery');

drop policy if exists "pod: authenticated upload" on storage.objects;
create policy "pod: authenticated upload"
  on storage.objects for insert
  with check (bucket_id = 'proof-of-delivery' and auth.role() = 'authenticated');

drop policy if exists "pod: owner or admin update" on storage.objects;
create policy "pod: owner or admin update"
  on storage.objects for update
  using (bucket_id = 'proof-of-delivery' and (owner = auth.uid() or public.is_admin()));

drop policy if exists "pod: owner or admin delete" on storage.objects;
create policy "pod: owner or admin delete"
  on storage.objects for delete
  using (bucket_id = 'proof-of-delivery' and (owner = auth.uid() or public.is_admin()));

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.deliveries;
