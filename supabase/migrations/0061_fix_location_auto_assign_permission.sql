-- SuperD: fixes a real bug in 0060_assign_pending_on_driver_location.sql,
-- found by manually testing the trigger it added - the pending delivery's
-- status flipped to 'assigned' but assigned_driver_id stayed null.
--
-- Cause: enforce_delivery_update() (the BEFORE UPDATE trigger on
-- deliveries that stops a non-dispatcher caller from reassigning a
-- delivery by hand) runs for every write to the table, including the one
-- 0060's assign_pending_deliveries_near_driver() makes. That write
-- happens inside the SAME transaction as a driver's own profile-location
-- update, under the driver's own JWT (security definer only changes
-- whose row-level privileges apply, not auth.uid() - that still reflects
-- the actual caller) - so enforce_delivery_update() saw a non-dispatcher
-- caller touching assigned_driver_id and silently reset it back to null,
-- exactly like it's supposed to for a driver trying to reassign a job by
-- hand. 0060's own trigger never anticipated needing an exception to it.
--
-- Fixed the same way 0056_delivery_completion_pin.sql already lets
-- complete_delivery_with_pin() bypass a different restriction in this
-- same function: a transaction-local flag
-- (superd.auto_assign_from_location) that assign_pending_deliveries_near_driver()
-- sets right before its own UPDATE, which enforce_delivery_update() now
-- checks alongside its existing is_driver_reject/is_driver_cancel
-- exceptions.

create or replace function public.assign_pending_deliveries_near_driver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.app_settings%rowtype;
  radius_km numeric;
  assign_cap integer;
  current_load integer;
  target_delivery_id uuid;
begin
  if not public.driver_daily_fee_paid(new.id) then
    return new;
  end if;

  select * into s from public.app_settings limit 1;
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);
  radius_km := coalesce(s.auto_assign_radius_km, 8);

  select count(*) into current_load
  from public.deliveries d
  where d.assigned_driver_id = new.id
    and d.status not in ('delivered', 'cancelled');

  if current_load >= assign_cap then
    return new;
  end if;

  select d.id into target_delivery_id
  from public.deliveries d
  join public.vendors v on v.id = d.vendor_id
  where d.status = 'pending'
    and d.assigned_driver_id is null
    and v.location_lat is not null and v.location_lng is not null
    and (d.scheduled_at is null or d.scheduled_at <= now() + interval '15 minutes')
    and 6371 * acos(least(1.0, greatest(-1.0,
      sin(radians(v.location_lat)) * sin(radians(new.last_lat))
      + cos(radians(v.location_lat)) * cos(radians(new.last_lat))
        * cos(radians(new.last_lng) - radians(v.location_lng))
    ))) <= radius_km
  order by
    6371 * acos(least(1.0, greatest(-1.0,
      sin(radians(v.location_lat)) * sin(radians(new.last_lat))
      + cos(radians(v.location_lat)) * cos(radians(new.last_lat))
        * cos(radians(new.last_lng) - radians(v.location_lng))
    ))) asc,
    d.created_at asc
  limit 1;

  if target_delivery_id is not null then
    perform set_config('superd.auto_assign_from_location', 'true', true);
    update public.deliveries
    set assigned_driver_id = new.id,
        status = 'assigned',
        assigned_at = now(),
        auto_assigned = true
    where id = target_delivery_id;
  end if;

  return new;
end;
$$;

-- Same signature as the version being replaced (0056_delivery_completion_pin.sql)
-- - everything unchanged except the one new exception described above.
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
