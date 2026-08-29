-- SuperD: the "active deliveries per driver" cap (app_settings.
-- zone_auto_assign_cap, set from Console > Settings) used to be a
-- ceiling on the *automatic* matching algorithm only - a dispatcher
-- assigning a driver by hand (DeliveryDetailAdminScreen's driver
-- dropdown) or creating a delivery already assigned to someone
-- (CreateDeliveryScreen) could always push a driver past it. That's no
-- longer what's wanted: an admin should be able to actually regulate how
-- many simultaneous deliveries any driver carries, no matter how the
-- assignment happens.
--
-- Added to enforce_delivery_update()/enforce_delivery_insert() - the
-- existing triggers (deliveries_enforce_update/deliveries_enforce_insert,
-- see 0001_init.sql/0025_driver_categories_and_status.sql) that already
-- backstop the frozen-driver and unpaid-commission rules against every
-- write to assigned_driver_id, whatever the caller. This is the one
-- place that check can't be bypassed - the RLS update/insert policies on
-- deliveries (0002_roles_step2_policies.sql) don't restrict which
-- columns a dispatcher can change, so a client-side-only check would
-- leave the direct-update path (assignDriver()/createDelivery()) unchecked.
--
-- Checked before the frozen/commission checks below it, since those
-- exist already and unpaid-commission has a side effect (spends a banked
-- free-day credit) that a rejected-anyway assignment shouldn't trigger.
--
-- Same signatures as the versions being replaced (enforce_delivery_update
-- from 0042_auto_assigned_indicator.sql, enforce_delivery_insert from
-- 0032_commission_free_days.sql) - everything else in both is unchanged.

create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
  is_driver_cancel boolean;
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
    if not (is_driver_reject or is_driver_cancel) then
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

  -- Whether the *current* assignment counts as "auto-assigned" for the
  -- badge: never true once unassigned, and a dispatcher choosing a driver
  -- by hand always overrides whatever it was before. driver_cancel_delivery()
  -- already set the right value on its own UPDATE (ahead of this trigger
  -- firing) for its same-zone hand-off, so is_driver_cancel is excluded
  -- here to avoid clobbering it - and in practice is_dispatcher_or_above()
  -- is false for that caller anyway (it's the driver who's cancelling).
  if new.assigned_driver_id is null then
    new.auto_assigned := false;
  elsif new.assigned_driver_id is distinct from old.assigned_driver_id
        and not is_driver_cancel
        and public.is_dispatcher_or_above()
  then
    new.auto_assigned := false;
  end if;

  -- Simultaneous-deliveries-per-driver cap - a hard limit, not just a
  -- hint to the automatic matcher, so this applies to a dispatcher
  -- reassigning by hand exactly like it does to submit_delivery_request()/
  -- driver_cancel_delivery()'s own candidate filtering.
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

  -- Same backstop for an unpaid daily commission - spends a free-day
  -- credit automatically if the driver has one banked and hasn't paid
  -- today, rather than just checking.
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

create or replace function public.enforce_delivery_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  active_count integer;
  driver_name text;
begin
  -- Simultaneous-deliveries-per-driver cap - see the matching check in
  -- enforce_delivery_update() above. OLD doesn't exist for an insert, so
  -- there's nothing to exclude from the count.
  if new.assigned_driver_id is not null then
    select coalesce(zone_auto_assign_cap, 5) into cap
    from public.app_settings limit 1;

    select count(*) into active_count
    from public.deliveries d
    where d.assigned_driver_id = new.assigned_driver_id
      and d.status not in ('delivered', 'cancelled');

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
     and exists (
       select 1 from public.profiles p
       where p.id = new.assigned_driver_id and p.is_frozen
     )
  then
    raise exception 'That driver is currently frozen and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and not public.claim_free_day_credit(new.assigned_driver_id)
  then
    raise exception 'That driver has not paid today''s commission yet and cannot be assigned new deliveries.';
  end if;

  return new;
end;
$$;
