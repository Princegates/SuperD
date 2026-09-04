-- SuperD: a "special delivery" - one a dispatcher/super admin creates by
-- hand from the Console with its own manually-priced fee, outside the
-- normal zone/road-distance auto-pricing that only applies to the public
-- customer-facing request flow (submit_delivery_request(), reached via a
-- vendor's link). CreateDeliveryScreen already let a dispatcher type in
-- an optional fee for any admin-created delivery; this makes that a real,
-- labeled category instead of just an untracked number, and (on the
-- client side - see the same PR) requires the fee once it's turned on
-- rather than leaving it skippable. Driver commission needs no separate
-- handling: log_commission_due() already computes it from whatever's
-- summed in `payments` for the delivery, regardless of how that payment
-- got there, so a special delivery's manually-entered fee already flows
-- into commission the same as any other delivery's.

alter table public.deliveries
  add column if not exists is_special boolean not null default false;

comment on column public.deliveries.is_special is 'True for a delivery a dispatcher/super admin created by hand with its own manually-entered fee, outside the normal zone/road-distance auto-pricing - see CreateDeliveryScreen. Purely a label for distinguishing/reporting on these; does not change how commission is calculated (see log_commission_due()).';

-- Same body as 0080_no_reassign_after_delivered.sql's version, plus
-- reverting is_special for a plain driver caller - same defensive
-- pattern as tracking_code/customer_name/etc above it: nothing in the
-- driver-facing app ever sends this column, but RLS shouldn't rely on
-- that being true forever.
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

  if old.status = 'delivered'
     and new.assigned_driver_id is distinct from old.assigned_driver_id
  then
    raise exception 'This delivery is already marked delivered - its assigned driver can no longer be changed.';
  end if;

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
    new.is_special := old.is_special;
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
