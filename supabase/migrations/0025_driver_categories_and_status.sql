-- SuperD: driver vehicle categories, online/offline availability, and a
-- super-admin "freeze" control (e.g. for unpaid commission) that blocks a
-- driver from taking on new work without locking them out of the app
-- entirely - they keep full access to whatever's already assigned to them.

do $$ begin
  create type public.driver_vehicle_type as enum ('motorbike', 'car', 'van_truck', 'tricycle');
exception
  when duplicate_object then null;
end $$;

alter table public.profiles
  add column if not exists vehicle_type public.driver_vehicle_type,
  add column if not exists is_online boolean not null default false,
  add column if not exists is_frozen boolean not null default false;

comment on column public.profiles.vehicle_type is 'Driver-only - what they deliver with. Groups/filters the driver roster in Team, and feeds the zone auto-assignment algorithm later.';
comment on column public.profiles.is_online is 'A driver toggles this themselves from their dashboard to say whether they''re available for new deliveries right now.';
comment on column public.profiles.is_frozen is 'Super-admin-only (see enforce_profile_role_change() below) - e.g. commission owed and unpaid. A frozen driver keeps full access to their existing/past deliveries but cannot accept a delivery still sitting at ''assigned'', and cannot be newly assigned one either.';

-- Pick up vehicle_type the same way vehicle_number already is, for a
-- dispatcher-created driver (admin-create-driver Edge Function). Self-
-- signup doesn't collect it yet, so it stays null until the driver (or a
-- dispatcher) sets it from their profile.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, phone, ghana_card_number, vehicle_number,
    vehicle_type, must_change_password, date_of_birth, residential_address,
    is_active
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'ghana_card_number',
    new.raw_user_meta_data ->> 'vehicle_number',
    nullif(new.raw_user_meta_data ->> 'vehicle_type', '')::public.driver_vehicle_type,
    coalesce((new.raw_user_meta_data ->> 'must_change_password')::boolean, false),
    nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date,
    new.raw_user_meta_data ->> 'residential_address',
    coalesce((new.raw_app_meta_data ->> 'created_by_admin')::boolean, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Extend the existing role-change guard: is_frozen is just as protected as
-- role now - a driver or dispatcher updating a profile can't unfreeze
-- themselves (or freeze someone else) by hand; only a super admin's
-- update is let through.
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
  if new.is_frozen is distinct from old.is_frozen and not public.is_super_admin() then
    new.is_frozen := old.is_frozen;
  end if;
  return new;
end;
$$;

-- A frozen driver can still finish work already under way, but can't
-- start something new: accepting a delivery still sitting at 'assigned'
-- (their one driver-initiated forward step before they've committed to
-- it - see DeliveryStatus.nextForDriver) is blocked, same as being
-- assigned a brand new one below. Rejecting stays allowed either way -
-- getting an unwanted job off a frozen driver's plate is never the wrong
-- move.
create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
begin
  is_driver_reject := (
    old.status = 'assigned'
    and new.status = 'pending'
    and old.assigned_driver_id = auth.uid()
    and new.assigned_driver_id is null
  );

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
    if not is_driver_reject then
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
  end if;

  -- Blocks assigning/reassigning a frozen driver from ANY caller,
  -- dispatcher included - the Console's driver picker already filters
  -- frozen drivers out, this is the real backstop underneath it.
  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and exists (
       select 1 from public.profiles p
       where p.id = new.assigned_driver_id and p.is_frozen
     )
  then
    raise exception 'That driver is currently frozen and cannot be assigned new deliveries.';
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

-- Same frozen-driver check for a delivery created with a driver already
-- picked - both the dispatcher "create delivery" form (assigns one up
-- front) and the zone auto-assignment algorithm inside
-- submit_delivery_request insert a driver at creation time, not just via
-- a later update.
create or replace function public.enforce_delivery_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_driver_id is not null
     and exists (
       select 1 from public.profiles p
       where p.id = new.assigned_driver_id and p.is_frozen
     )
  then
    raise exception 'That driver is currently frozen and cannot be assigned new deliveries.';
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_enforce_insert on public.deliveries;
create trigger deliveries_enforce_insert
  before insert on public.deliveries
  for each row execute function public.enforce_delivery_insert();
