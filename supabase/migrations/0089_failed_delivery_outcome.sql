-- SuperD: "the rider went, and the parcel did not change hands."
--
-- Until now that ended as `cancelled`, the same status a dispatcher sets
-- when killing an order nobody ever rode for. Those are two different
-- facts about the business and they were being written down identically:
-- you could not tell, at the end of a month, how many customers were not
-- home, how many addresses were wrong, or which rider that keeps
-- happening to.
--
-- WHY THIS IS NOT A NEW `delivery_status` VALUE
--
-- The obvious move is `alter type delivery_status add value 'failed'`.
-- It is the wrong one here. Roughly sixty places in this schema ask
-- "is this delivery still live?" as `status not in ('delivered',
-- 'cancelled')` - the assignment cap, every auto-assignment candidate
-- query, the zone workload ordering, the location-triggered assigner. A
-- new enum value is *absent* from all of them, so a failed delivery
-- would silently keep occupying its rider's capacity forever, and each
-- of those functions would have to be re-created to fix it, by hand, in
-- the console, days before launch.
--
-- A failed delivery is mechanically identical to a cancelled one:
-- terminal, no fare collected, no commission owed (log_commission_due
-- fires on `delivered` only), frees the rider. The only thing that
-- differs is *meaning*. So the status stays `cancelled` and the meaning
-- goes in its own column, which nothing existing has to learn about.
-- `failure_reason is not null` is the discriminator; the app reads it and
-- says "Failed - customer absent" wherever it would have said
-- "Cancelled".
--
-- If failed deliveries ever need to behave differently from cancelled
-- ones mechanically, promoting this to an enum value is still open, with
-- the reasons already recorded to backfill from.

do $$ begin
  create type public.delivery_failure_reason as enum (
    'customer_absent',    -- rider arrived, nobody there
    'customer_refused',   -- customer there, would not take it
    'wrong_address',      -- address does not exist / is not theirs
    'unreachable',        -- phone off, no answer, no way to hand over
    'package_issue',      -- damaged, wrong item, nothing to collect
    'other'
  );
exception
  when duplicate_object then null;
end $$;

alter table public.deliveries
  add column if not exists failure_reason public.delivery_failure_reason,
  add column if not exists failure_note text,
  add column if not exists failed_at timestamptz,
  add column if not exists failed_by uuid references public.profiles(id) on delete set null;

comment on column public.deliveries.failure_reason is 'Set when a delivery ended without a hand-over despite someone riding for it. Status is still `cancelled` (see 0089) - this column is what separates a failed delivery from one a dispatcher called off.';
comment on column public.deliveries.failure_note is 'The rider''s own words, when they added any. Free text - the reason enum is what reporting counts.';
comment on column public.deliveries.failed_by is 'Who recorded the failure - the assigned rider, or the dispatcher who logged it on their behalf.';

-- Reporting only ever wants the failed ones, and they are a small slice
-- of a table that grows forever.
create index if not exists deliveries_failure_reason_idx
  on public.deliveries (failure_reason, failed_at desc)
  where failure_reason is not null;

-- ---------------------------------------------------------------------------
-- enforce_delivery_update: recreated from 0081 with one addition.
--
-- A rider is not a dispatcher, so the trigger blanks the fields they are
-- not allowed to set. The failure columns have to be reachable by them
-- for exactly one transition - ending their own live job as failed - and
-- frozen the rest of the time, so a rider cannot relabel a delivered job
-- or edit someone else's outcome. `is_driver_fail` below is that one
-- transition, in the same shape as the reject/cancel exceptions above it.
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
  is_driver_fail boolean;
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

  is_driver_fail := (
    old.status in ('assigned', 'picked_up', 'in_transit')
    and old.assigned_driver_id = auth.uid()
    and new.status = 'cancelled'
    and new.failure_reason is not null
    and old.failure_reason is null
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
    if not is_driver_fail then
      new.failure_reason := old.failure_reason;
      new.failure_note := old.failure_note;
      new.failed_at := old.failed_at;
      new.failed_by := old.failed_by;
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

  -- A delivered job is finished. Relabelling it as failed afterwards
  -- would take a fare and a commission off the books after the fact, so
  -- it is refused for everyone, dispatchers included.
  if old.status = 'delivered' and new.failure_reason is not null then
    raise exception 'This delivery was completed - it cannot be recorded as failed.';
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
  -- Stamped here rather than by each caller, so a failure recorded from
  -- the console carries the same timestamp and author as one recorded by
  -- the rider on the road.
  if new.failure_reason is not null and old.failure_reason is null then
    new.failed_at := coalesce(new.failed_at, now());
    new.failed_by := coalesce(new.failed_by, auth.uid());
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- fail_delivery(): the one way this outcome gets recorded.
--
-- Two callers, deliberately the same function. The rider taps "Couldn't
-- deliver" on the road; the dispatcher records it from the console when
-- the rider phoned it in instead. Same row, same reason list, same
-- history note - so a month's failures are comparable no matter who typed
-- them in.
--
-- A rider may only fail a job that is currently theirs and still live.
-- Everything else - somebody else's delivery, one already finished - is
-- refused with a sentence they can act on rather than a policy violation.
-- ---------------------------------------------------------------------------
create or replace function public.fail_delivery(
  p_delivery_id uuid,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.deliveries%rowtype;
  reason public.delivery_failure_reason;
  actor_name text;
  clean_note text;
  is_staff boolean;
begin
  begin
    reason := p_reason::public.delivery_failure_reason;
  exception when invalid_text_representation then
    raise exception 'Unknown failure reason: %', p_reason;
  end;

  is_staff := public.is_dispatcher_or_above();
  clean_note := nullif(trim(coalesce(p_note, '')), '');

  select * into d from public.deliveries where id = p_delivery_id for update;
  if not found then
    raise exception 'That delivery no longer exists.';
  end if;

  if d.status = 'delivered' then
    raise exception 'This delivery was completed - it cannot be recorded as failed.';
  end if;
  if d.failure_reason is not null then
    raise exception 'This delivery is already recorded as failed.';
  end if;

  if not is_staff then
    if d.assigned_driver_id is distinct from auth.uid() then
      raise exception 'This delivery is not assigned to you.';
    end if;
    if d.status not in ('assigned', 'picked_up', 'in_transit') then
      raise exception 'This delivery is no longer active.';
    end if;
  end if;

  select nullif(trim(full_name), '') into actor_name
  from public.profiles where id = auth.uid();

  -- Reads as prose in the delivery's history, because that is where a
  -- dispatcher goes to find out what happened. The rider's own note is
  -- left exactly as they typed it, punctuation and all, rather than
  -- being wrapped in ours.
  perform set_config(
    'superd.status_note',
    format(
      'Failed - %s. Recorded by %s.%s',
      replace(reason::text, '_', ' '),
      coalesce(actor_name, 'staff'),
      case when clean_note is null then '' else ' ' || clean_note end
    ),
    true
  );

  update public.deliveries
  set status = 'cancelled',
      failure_reason = reason,
      failure_note = clean_note,
      failed_at = now(),
      failed_by = auth.uid()
  where id = p_delivery_id;
end;
$$;

revoke all on function public.fail_delivery(uuid, text, text) from public;
grant execute on function public.fail_delivery(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- What the failures add up to. Reporting wants the shape of the problem -
-- which reason, how often, and how much fare walked away with it - not a
-- list of rows to count by hand.
--
-- Invoker rights on purpose: `deliveries` already decides who may read
-- what, and this must not become a way around that.
-- ---------------------------------------------------------------------------
create or replace function public.failed_delivery_summary(
  p_since timestamptz default null
)
returns table (
  reason text,
  failures bigint,
  lost_fare numeric
)
language sql
stable
set search_path = public
as $$
  select
    d.failure_reason::text,
    count(*),
    coalesce(sum(p.amount), 0)
  from public.deliveries d
  left join public.payments p on p.delivery_id = d.id
  where d.failure_reason is not null
    and (p_since is null or d.failed_at >= p_since)
  group by d.failure_reason
  order by count(*) desc;
$$;

grant execute on function public.failed_delivery_summary(timestamptz) to authenticated;
