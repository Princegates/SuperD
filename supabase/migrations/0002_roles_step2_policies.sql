-- SuperD: three-tier roles - STEP 2 of 2.
--
-- Run 0002_roles_step1_enum.sql FIRST and let it finish. Then run this
-- file separately.
--
-- Splits the old single "admin" role into two tiers:
--   dispatcher   - day-to-day operations: creates deliveries, assigns
--                  drivers, sees everything. (This is what "admin" used
--                  to mean in 0001_init.sql - existing admin accounts
--                  became dispatchers automatically via step 1's rename.)
--   super_admin  - everything a dispatcher can do, PLUS managing other
--                  users' roles (promote/demote) from within the app.
--   driver       - unchanged: field courier, sees only their own jobs.

-- ---------------------------------------------------------------------------
-- Helper functions (replace the old is_admin()).
-- ---------------------------------------------------------------------------
create or replace function public.is_dispatcher_or_above()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('dispatcher', 'super_admin')
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- profiles: only a super admin may change someone's role. Every other
-- dispatcher-or-above-permitted update (e.g. is_active) still goes through,
-- but a role change silently snaps back unless the caller is a super admin -
-- defense in depth on top of the RLS policy below.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_super_admin() then
    new.role := old.role;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_enforce_role_change on public.profiles;
create trigger profiles_enforce_role_change
  before update on public.profiles
  for each row execute function public.enforce_profile_role_change();

-- ---------------------------------------------------------------------------
-- Re-point every policy/trigger that referenced is_admin() at the new
-- functions, then drop is_admin() now that nothing depends on it.
-- ---------------------------------------------------------------------------
drop policy if exists "profiles: read own or admin reads all" on public.profiles;
create policy "profiles: read own or dispatcher reads all"
  on public.profiles for select
  using (id = auth.uid() or public.is_dispatcher_or_above());

drop policy if exists "profiles: user updates own non-role fields" on public.profiles;
create policy "profiles: user updates own non-role fields"
  on public.profiles for update
  using (id = auth.uid() or public.is_dispatcher_or_above())
  with check (id = auth.uid() or public.is_dispatcher_or_above());

drop policy if exists "profiles: admin inserts" on public.profiles;
create policy "profiles: dispatcher inserts"
  on public.profiles for insert
  with check (public.is_dispatcher_or_above());

drop policy if exists "deliveries: admin full read" on public.deliveries;
create policy "deliveries: dispatcher full read"
  on public.deliveries for select
  using (public.is_dispatcher_or_above() or assigned_driver_id = auth.uid());

drop policy if exists "deliveries: admin insert" on public.deliveries;
create policy "deliveries: dispatcher insert"
  on public.deliveries for insert
  with check (public.is_dispatcher_or_above());

drop policy if exists "deliveries: admin or assigned driver update" on public.deliveries;
create policy "deliveries: dispatcher or assigned driver update"
  on public.deliveries for update
  using (public.is_dispatcher_or_above() or assigned_driver_id = auth.uid());

drop policy if exists "deliveries: admin delete" on public.deliveries;
create policy "deliveries: dispatcher delete"
  on public.deliveries for delete
  using (public.is_dispatcher_or_above());

drop policy if exists "history: admin or assigned driver read" on public.delivery_status_history;
create policy "history: dispatcher or assigned driver read"
  on public.delivery_status_history for select
  using (
    public.is_dispatcher_or_above()
    or exists (
      select 1 from public.deliveries d
      where d.id = delivery_id and d.assigned_driver_id = auth.uid()
    )
  );

drop policy if exists "pod: owner or admin update" on storage.objects;
create policy "pod: owner or dispatcher update"
  on storage.objects for update
  using (bucket_id = 'proof-of-delivery' and (owner = auth.uid() or public.is_dispatcher_or_above()));

drop policy if exists "pod: owner or admin delete" on storage.objects;
create policy "pod: owner or dispatcher delete"
  on storage.objects for delete
  using (bucket_id = 'proof-of-delivery' and (owner = auth.uid() or public.is_dispatcher_or_above()));

create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_dispatcher_or_above() then
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

drop function if exists public.is_admin();
