-- SuperD: three related additions around a driver rejecting or abandoning
-- a delivery already under way.
--
-- 1. `delivery_status_history.note` (already existed, unused until now)
--    gets filled in for two specific transitions - a driver rejecting a
--    delivery before starting it, and a driver cancelling one already
--    picked up - via a transaction-local Postgres setting
--    (`superd.status_note`) that `log_delivery_status_change()` reads,
--    rather than every ordinary status update needing to know about it.
--    This is what "more detail in the report" comes from - the note is a
--    full sentence naming the driver and what happened, not just a bare
--    status change.
--
-- 2. `driver_cancel_delivery()` - new. Unlike reject (only reachable
--    before accepting, sends the delivery back to the unassigned pool),
--    this is for a driver already committed (picked_up/in_transit) who
--    can't finish the job. Tries to auto-reassign to another available
--    driver in the same zone (same selection logic as
--    submit_delivery_request's auto-assignment), falling back to
--    'pending' - unassigned, needs a dispatcher - only if nobody's free.
--    An admin can always override either outcome by hand from the
--    existing delivery detail screen's driver dropdown, same as any
--    other delivery.
--
-- 3. `app_settings.admin_alert_email`/`admin_alert_phone` - where the
--    cancellation alert (see notify-delivery-events) reaches an admin.
--    Deliberately separate from `support_phone`, which customers/vendors
--    call, not the business's own internal alert channel.

alter table public.app_settings
  add column if not exists admin_alert_email text;

comment on column public.app_settings.admin_alert_email is 'Where an internal alert (e.g. a driver cancelling mid-trip) is emailed - separate from support_phone, which is customer/vendor-facing, not an internal channel.';

alter table public.app_settings
  add column if not exists admin_alert_phone text;

comment on column public.app_settings.admin_alert_phone is 'Where an internal alert (e.g. a driver cancelling mid-trip) is texted - separate from support_phone, which is customer/vendor-facing, not an internal channel.';

-- Fills in the note for whichever transition set superd.status_note just
-- before the update that fires this trigger - null (unchanged) for every
-- ordinary status change, which is the vast majority of them.
create or replace function public.log_delivery_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.delivery_status_history (delivery_id, status, changed_by, note)
    values (
      new.id, new.status, auth.uid(),
      nullif(current_setting('superd.status_note', true), '')
    );
  end if;
  return new;
end;
$$;

-- Same signature/behavior as 0023 - now also names the rejecting driver
-- in the history note instead of leaving it blank.
create or replace function public.driver_reject_delivery(p_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  driver_name text;
begin
  select full_name into driver_name from public.profiles where id = auth.uid();

  perform set_config(
    'superd.status_note',
    format(
      'Rejected by %s before starting the trip.',
      coalesce(driver_name, 'the driver')
    ),
    true
  );

  update public.deliveries
  set status = 'pending',
      assigned_driver_id = null
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status = 'assigned';

  if not found then
    raise exception 'This delivery can no longer be rejected - it may already have been picked up or reassigned.';
  end if;
end;
$$;

-- Adds the one narrow exception driver_cancel_delivery() needs, the same
-- way 0023 added one for reject: a driver may not normally touch
-- assigned_driver_id at all (that's what stops them reassigning jobs to
-- themselves or anyone else), except for clearing their own assignment
-- (reject) or - now - handing an already-accepted job to a replacement
-- driver (or back to the unassigned pool) when they can't finish it.
create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
  is_driver_cancel boolean;
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

-- A driver who already accepted a delivery (picked_up or in_transit) but
-- can't finish it - a breakdown, an emergency, whatever - hands it off
-- instead of just leaving it stuck assigned to them. Tries to find
-- another driver in the same zone first (same eligibility rules as
-- auto-assignment on a new request: online, active, not frozen, paid up
-- on today's fee, under the zone's assignment cap, preferring whoever
-- already has the most work in this zone); if nobody qualifies, the
-- delivery falls back to 'pending' for a dispatcher to hand out by hand -
-- either way it's recorded with a full sentence explaining what happened
-- (see log_delivery_status_change() above), and notify-delivery-events
-- alerts an admin by email/SMS.
create or replace function public.driver_cancel_delivery(
  p_delivery_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.deliveries%rowtype;
  s public.app_settings%rowtype;
  old_driver_name text;
  new_driver_name text;
  target_driver_id uuid;
  target_status public.delivery_status;
  assign_cap integer;
  reason_suffix text;
  note_text text;
begin
  select * into d from public.deliveries
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status in ('picked_up', 'in_transit')
  for update;

  if not found then
    raise exception 'This delivery can no longer be cancelled - it may already have been delivered or reassigned.';
  end if;

  select full_name into old_driver_name from public.profiles where id = auth.uid();
  select * into s from public.app_settings limit 1;
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);

  reason_suffix := case
    when p_reason is not null and length(trim(p_reason)) > 0
      then ' (' || trim(p_reason) || ')'
    else ''
  end;

  if d.zone_id is not null then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.id <> auth.uid()
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.zone_id = d.zone_id
      and public.driver_daily_fee_paid(p.id)
      and (
        select count(*) from public.deliveries dd
        where dd.assigned_driver_id = p.id
          and dd.zone_id = d.zone_id
          and dd.status not in ('delivered', 'cancelled')
      ) < assign_cap
    order by
      (
        select count(*) from public.deliveries dd
        where dd.assigned_driver_id = p.id
          and dd.zone_id = d.zone_id
          and dd.status not in ('delivered', 'cancelled')
      ) desc,
      (
        select count(*) from public.deliveries dd
        where dd.assigned_driver_id = p.id
          and dd.status not in ('delivered', 'cancelled')
      ) asc,
      p.full_name
    limit 1;
  end if;

  if target_driver_id is not null then
    select full_name into new_driver_name from public.profiles where id = target_driver_id;
    target_status := 'assigned';
    note_text := format(
      'Cancelled by %s mid-trip%s - reassigned to %s.',
      coalesce(old_driver_name, 'the driver'), reason_suffix,
      coalesce(new_driver_name, 'another driver')
    );
  else
    target_status := 'pending';
    note_text := format(
      'Cancelled by %s mid-trip%s - no other driver available, needs manual reassignment.',
      coalesce(old_driver_name, 'the driver'), reason_suffix
    );
  end if;

  perform set_config('superd.status_note', note_text, true);

  update public.deliveries
  set status = target_status,
      assigned_driver_id = target_driver_id,
      assigned_at = null,
      picked_up_at = null
  where id = p_delivery_id;
end;
$$;

grant execute on function public.driver_cancel_delivery(uuid, text) to authenticated;
