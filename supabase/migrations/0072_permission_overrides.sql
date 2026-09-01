-- SuperD: per-staff-member permission overrides on top of the existing
-- role model. Until now what a dispatcher/auditor could do was entirely
-- decided by is_dispatcher_or_above()/is_auditor() - same for every
-- account with that role, no way to fine-tune one specific person. This
-- adds a super-admin-editable override on individual accounts for four
-- actions to start: creating a delivery, managing the driver roster
-- (add/edit/remove), assigning a driver to a delivery, and managing
-- vendors (add/edit/remove) - e.g. a dispatcher who shouldn't be able to
-- add vendors, or an auditor specifically allowed to create deliveries.
-- More actions can be added the same way later (a new key in
-- role_default_permission(), no new column needed).
--
-- Design: profiles.permission_overrides is a jsonb object. A permission
-- key present in it (true or false) always wins; a key absent from it
-- falls back to whatever role_default_permission() says the account's
-- role gets by default - which, for these four keys, is exactly today's
-- is_dispatcher_or_above() behavior (true for dispatcher/auditor/super
-- admin, false for driver), so every existing account behaves identically
-- until a super admin actually sets an override.

alter table public.profiles
  add column if not exists permission_overrides jsonb not null default '{}'::jsonb;

comment on column public.profiles.permission_overrides is
  'Per-account overrides on top of role_default_permission() - a key '
  'present here (true or false) wins over the role default; a key absent '
  'falls back to the role default. Only a super admin may write this '
  'column - see enforce_permission_overrides_change() below, same footing '
  'as a role change.';

-- What a role gets by default, before any override. Its own function
-- (not inlined into has_permission()) so adding a new permission key, or
-- a role whose default differs from "same as dispatcher", is a one-line
-- change here rather than touching every call site.
create or replace function public.role_default_permission(p_role public.user_role, p_permission text)
returns boolean
language sql
immutable
as $$
  select case
    when p_role = 'super_admin' then true
    when p_role in ('dispatcher', 'auditor')
         and p_permission in (
           'create_deliveries', 'manage_drivers', 'assign_drivers', 'manage_vendors'
         )
      then true
    else false
  end;
$$;

-- A super admin is unconditionally true, same as is_super_admin() itself -
-- never overridable, even by a stray override row (there's no UI to set
-- one on a super admin, but this is the backstop if that ever happened).
-- Anyone else: their own override if they have one for this key, else
-- their role's default.
create or replace function public.has_permission(p_user_id uuid, p_permission text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when (select p.role from public.profiles p where p.id = p_user_id) = 'super_admin'
      then true
    else coalesce(
      (
        select (p.permission_overrides ->> p_permission)::boolean
        from public.profiles p
        where p.id = p_user_id
      ),
      (
        select public.role_default_permission(p.role, p_permission)
        from public.profiles p
        where p.id = p_user_id
      ),
      false
    )
  end;
$$;

grant execute on function public.has_permission(uuid, text) to authenticated;

-- Only a super admin may change permission_overrides - the same footing
-- as enforce_profile_role_change() already gives `role` itself. Together
-- role + these overrides decide everything an account can do, so both
-- need the same guard.
create or replace function public.enforce_permission_overrides_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.permission_overrides is distinct from old.permission_overrides
     and not public.is_super_admin()
     and auth.role() is distinct from 'service_role' then
    new.permission_overrides := old.permission_overrides;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_permission_overrides_change on public.profiles;
create trigger trg_enforce_permission_overrides_change
  before update on public.profiles
  for each row execute function public.enforce_permission_overrides_change();

-- ---------------------------------------------------------------------------
-- 1. Creating a delivery: was any dispatcher-or-above, now needs the
--    specific permission.
-- ---------------------------------------------------------------------------
drop policy if exists "deliveries: dispatcher insert" on public.deliveries;
create policy "deliveries: permitted staff insert"
  on public.deliveries for insert
  with check (public.has_permission(auth.uid(), 'create_deliveries'));

-- ---------------------------------------------------------------------------
-- 2. Managing vendors: register_vendor() is SECURITY DEFINER and callable
--    directly by any authenticated user (not just from the RLS-governed
--    `vendors` table), since it also serves the anonymous public
--    self-signup path (via the public-register-vendor Edge Function,
--    which calls it with the service-role key - auth.uid() is null for
--    that path, left untouched below). Editing/deactivating/deleting an
--    existing vendor IS a direct table operation, so those three get
--    ordinary RLS policies same as everything else.
-- ---------------------------------------------------------------------------
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
  if auth.uid() is not null and not public.has_permission(auth.uid(), 'manage_vendors') then
    raise exception 'You do not have permission to add a vendor.';
  end if;

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

drop policy if exists "vendors: dispatcher manages" on public.vendors;

drop policy if exists "vendors: dispatcher or above reads" on public.vendors;
create policy "vendors: dispatcher or above reads"
  on public.vendors for select
  using (public.is_dispatcher_or_above());

drop policy if exists "vendors: permitted staff insert" on public.vendors;
create policy "vendors: permitted staff insert"
  on public.vendors for insert
  with check (public.has_permission(auth.uid(), 'manage_vendors'));

drop policy if exists "vendors: permitted staff updates" on public.vendors;
create policy "vendors: permitted staff updates"
  on public.vendors for update
  using (public.has_permission(auth.uid(), 'manage_vendors'))
  with check (public.has_permission(auth.uid(), 'manage_vendors'));

drop policy if exists "vendors: permitted staff deletes" on public.vendors;
create policy "vendors: permitted staff deletes"
  on public.vendors for delete
  using (public.has_permission(auth.uid(), 'manage_vendors'));

-- ---------------------------------------------------------------------------
-- 3. Managing the driver roster: narrows the two policies
--    0054_auditor_role_permissions.sql already split out for a driver row
--    specifically (an auditor could always touch a driver row; a plain
--    dispatcher/super admin could touch any non-driver row too - both of
--    those stay exactly as they were, only the driver-row branch now also
--    needs the permission). Actual account creation/deletion for a driver
--    goes through the admin-create-driver/admin-delete-driver Edge
--    Functions (service-role, bypasses RLS) - those get their own
--    has_permission() check below, this is for direct profile edits
--    (approve/deactivate, update details, change zone, etc).
-- ---------------------------------------------------------------------------
drop policy if exists "profiles: user updates own non-role fields" on public.profiles;
create policy "profiles: user updates own non-role fields"
  on public.profiles for update
  using (
    id = auth.uid()
    or (role != 'driver' and public.is_dispatcher_or_above() and not public.is_auditor())
    or (role = 'driver' and public.has_permission(auth.uid(), 'manage_drivers'))
  )
  with check (
    id = auth.uid()
    or (role != 'driver' and public.is_dispatcher_or_above() and not public.is_auditor())
    or (role = 'driver' and public.has_permission(auth.uid(), 'manage_drivers'))
  );

drop policy if exists "profiles: dispatcher inserts" on public.profiles;
create policy "profiles: permitted staff insert"
  on public.profiles for insert
  with check (
    (role != 'driver' and public.is_dispatcher_or_above() and not public.is_auditor())
    or (role = 'driver' and public.has_permission(auth.uid(), 'manage_drivers'))
  );

-- ---------------------------------------------------------------------------
-- 4. Assigning a driver to a delivery: the broad "dispatcher or assigned
--    driver update" RLS policy on `deliveries` (0002_roles_step2_policies.sql)
--    covers every kind of update a dispatcher-or-above makes (status,
--    notes, zone override, and driver assignment alike), so it can't be
--    the enforcement point for one specific column - narrowing it would
--    also block the other, unrelated updates the same permission-lacking
--    account is still allowed to make. enforce_delivery_update() already
--    reverts specific columns a plain driver caller has no business
--    touching (see the `if not is_dispatcher_or_above()` branch above);
--    this is the same pattern one level up, for a dispatcher-or-above
--    caller who lacks assign_drivers specifically. Raises instead of
--    silently reverting (unlike the driver-column reset above) since the
--    "Assign driver" control really did just try this and should show an
--    error, not a silent no-op.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
  is_driver_cancel boolean;
  is_auto_assign_from_location boolean;
  cap integer;
  active_count integer;
  driver_name text;
begin
  is_driver_reject := (
    old.status = 'assigned'
    and new.status = 'pending'
    and old.assigned_driver_id = auth.uid()
    and new.assigned_driver_id is null
  );

  is_driver_cancel := (
    old.status in ('picked_up', 'in_transit')
    and old.assigned_driver_id = auth.uid()
    and new.status in ('assigned', 'pending')
    and new.assigned_driver_id is distinct from old.assigned_driver_id
  );

  is_auto_assign_from_location := coalesce(
    current_setting('superd.auto_assign_from_location', true), ''
  ) = 'true';

  if not public.is_dispatcher_or_above() then
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
    if not (is_driver_reject or is_driver_cancel or is_auto_assign_from_location) then
      new.assigned_driver_id := old.assigned_driver_id;
      new.assigned_at := old.assigned_at;
    end if;

    if old.status = 'assigned'
       and new.status is distinct from 'assigned'
       and not is_driver_reject
       and exists (
         select 1 from public.profiles p
         where p.id = auth.uid() and p.is_frozen
       )
    then
      raise exception 'Your account is currently frozen - contact dispatch before accepting new deliveries.';
    end if;

    if new.status = 'delivered'
       and old.status is distinct from 'delivered'
       and coalesce(current_setting('superd.pin_verified', true), '') is distinct from 'true'
    then
      raise exception 'Enter the delivery PIN the customer gives you to mark this delivered.';
    end if;

    if old.status = 'delivered' and new.status is distinct from 'delivered' then
      raise exception 'This delivery is already marked delivered and cannot be undone - the customer already confirmed receipt with the PIN.';
    end if;
  end if;

  if public.is_dispatcher_or_above()
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and not is_driver_reject
     and not is_driver_cancel
     and not is_auto_assign_from_location
     and not public.has_permission(auth.uid(), 'assign_drivers')
  then
    raise exception 'You do not have permission to assign drivers to a delivery.';
  end if;

  if new.assigned_driver_id is null then
    new.auto_assigned := false;
  elsif new.assigned_driver_id is distinct from old.assigned_driver_id
        and not is_driver_cancel
        and public.is_dispatcher_or_above()
  then
    new.auto_assigned := false;
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
  then
    select coalesce(zone_auto_assign_cap, 5) into cap
    from public.app_settings limit 1;

    select count(*) into active_count
    from public.deliveries d
    where d.assigned_driver_id = new.assigned_driver_id
      and d.status not in ('delivered', 'cancelled')
      and d.id <> old.id;

    if active_count >= cap then
      select full_name into driver_name
      from public.profiles where id = new.assigned_driver_id;

      raise exception
        '% already has % active deliveries, at the cap of %. Raise the '
        'cap in Console > Settings or assign someone else.',
        coalesce(driver_name, 'This driver'), active_count, cap;
    end if;
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and exists (
       select 1 from public.profiles p
       where p.id = new.assigned_driver_id and p.is_frozen
     )
  then
    raise exception 'That driver is currently frozen and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and not public.claim_free_day_credit(new.assigned_driver_id)
  then
    raise exception 'That driver has not paid today''s commission yet and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and public.driver_has_overdue_commission(new.assigned_driver_id)
  then
    raise exception 'That driver has unsettled commission from a previous day and cannot be assigned new deliveries until it''s paid or waived.';
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
