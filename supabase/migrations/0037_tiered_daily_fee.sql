-- SuperD: replaces the flat driver daily fee with a tiered one, priced by
-- how many deliveries the driver has completed *today* so far - a super
-- admin defines any number of tiers ("at least N deliveries today -> pay
-- X"), and the amount owed re-evaluates live as the driver completes more
-- deliveries during the day, same as the flat fee always did (it's still
-- a hard block: unpaid means no new delivery), just no longer a single
-- app-wide number.
--
-- A tier is expressed as a threshold, not a min/max range, so the table
-- can never have gaps or overlaps: "min_deliveries: 0 -> 10, min_deliveries:
-- 6 -> 15" reads as "0 or more completed today: 10; 6 or more: 15" - the
-- highest threshold the driver has reached wins. No tiers at all = the
-- whole feature is off, same meaning as the old flat fee being 0.
--
-- Because the amount owed can now change during the day (crossing into a
-- higher tier), a driver may need to pay more than once in the same day -
-- so `driver_daily_fees` drops its old one-row-per-driver-per-day unique
-- constraint in favor of "the sum of everything paid/waived today".

alter table public.app_settings
  drop constraint if exists app_settings_driver_daily_fee_check;

alter table public.app_settings
  drop column if exists driver_daily_fee;

create table if not exists public.driver_daily_fee_tiers (
  id uuid primary key default gen_random_uuid(),
  min_deliveries integer not null unique check (min_deliveries >= 0),
  amount numeric(10, 2) not null check (amount > 0),
  created_at timestamptz not null default now()
);

comment on table public.driver_daily_fee_tiers is 'Admin-defined tiers for the driver daily fee: a driver who has completed at least min_deliveries deliveries today owes amount for the day (the highest matching tier wins). Empty table = feature off, same meaning the flat fee''s 0 used to have.';

alter table public.driver_daily_fee_tiers enable row level security;

drop policy if exists "driver_daily_fee_tiers: anyone reads" on public.driver_daily_fee_tiers;
create policy "driver_daily_fee_tiers: anyone reads"
  on public.driver_daily_fee_tiers for select
  using (true);

drop policy if exists "driver_daily_fee_tiers: super admin inserts" on public.driver_daily_fee_tiers;
create policy "driver_daily_fee_tiers: super admin inserts"
  on public.driver_daily_fee_tiers for insert
  with check (public.is_super_admin());

drop policy if exists "driver_daily_fee_tiers: super admin updates" on public.driver_daily_fee_tiers;
create policy "driver_daily_fee_tiers: super admin updates"
  on public.driver_daily_fee_tiers for update
  using (public.is_super_admin())
  with check (public.is_super_admin());

drop policy if exists "driver_daily_fee_tiers: super admin deletes" on public.driver_daily_fee_tiers;
create policy "driver_daily_fee_tiers: super admin deletes"
  on public.driver_daily_fee_tiers for delete
  using (public.is_super_admin());

alter publication supabase_realtime add table public.driver_daily_fee_tiers;

-- The old unique(driver_id, fee_date) meant "at most one payment record
-- per driver per day" - no longer true once a driver can owe a second,
-- larger amount after crossing a tier mid-day. A plain index keeps
-- per-driver-per-day lookups fast without that constraint.
alter table public.driver_daily_fees drop constraint if exists driver_daily_fees_driver_id_fee_date_key;
create index if not exists driver_daily_fees_driver_date_idx on public.driver_daily_fees (driver_id, fee_date);

-- How many deliveries [p_driver_id] has completed on [p_day] - the count
-- that picks their tier. "Completed" = marked delivered that calendar day,
-- not just assigned/in-progress.
create or replace function public.driver_completed_deliveries_on(
  p_driver_id uuid,
  p_day date default current_date
)
returns integer
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::integer
  from public.deliveries
  where assigned_driver_id = p_driver_id
    and status = 'delivered'
    and delivered_at::date = p_day;
$$;

grant execute on function public.driver_completed_deliveries_on(uuid, date) to authenticated;

-- The tier amount [p_driver_id] owes for [p_day], based on their completed
-- count on that day - the highest tier whose min_deliveries they've
-- reached, or 0 if no tiers are configured (feature off) or none apply yet.
create or replace function public.driver_daily_fee_amount(
  p_driver_id uuid,
  p_day date default current_date
)
returns numeric
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select t.amount
      from public.driver_daily_fee_tiers t
      where t.min_deliveries <= public.driver_completed_deliveries_on(p_driver_id, p_day)
      order by t.min_deliveries desc
      limit 1
    ),
    0
  );
$$;

grant execute on function public.driver_daily_fee_amount(uuid, date) to authenticated;

-- Total already paid or waived toward [p_day]'s fee - can span more than
-- one row now that a driver may top up after crossing into a higher tier.
create or replace function public.driver_daily_fee_paid_amount(
  p_driver_id uuid,
  p_day date default current_date
)
returns numeric
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(sum(amount), 0)
  from public.driver_daily_fees
  where driver_id = p_driver_id
    and fee_date = p_day
    and status in ('paid', 'waived');
$$;

grant execute on function public.driver_daily_fee_paid_amount(uuid, date) to authenticated;

-- Whatever [p_driver_id] still owes for [p_day] right now - 0 once a
-- waive_daily_fee() row exists for that day (a full waiver, regardless of
-- tier), otherwise the current tier amount minus whatever's already been
-- paid/waived. This is the number actually charged - via Hubtel or shown
-- for a manual reference - never the client-supplied one.
create or replace function public.driver_daily_fee_balance(
  p_driver_id uuid,
  p_day date default current_date
)
returns numeric
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  owed numeric;
  paid numeric;
begin
  if exists (
    select 1 from public.driver_daily_fees
    where driver_id = p_driver_id and fee_date = p_day and status = 'waived'
  ) then
    return 0;
  end if;

  owed := public.driver_daily_fee_amount(p_driver_id, p_day);
  paid := public.driver_daily_fee_paid_amount(p_driver_id, p_day);
  return greatest(owed - paid, 0);
end;
$$;

grant execute on function public.driver_daily_fee_balance(uuid, date) to authenticated;

-- Whether [p_driver_id] is clear to be assigned deliveries on [p_day] -
-- same signature/meaning as before (used by `unpaid_driver_ids_today()`
-- and the zone-candidate filter in `submit_delivery_request`), now backed
-- by the tiered balance instead of one flat app-wide number. Still counts
-- an unspent free-day credit as "clear" for *today* specifically, without
-- spending it - a driver isn't excluded from being considered just because
-- they haven't actually had the credit applied yet; only
-- `claim_free_day_credit()` below actually spends one, at the one moment
-- (a real, committed assignment) that's safe to do so.
create or replace function public.driver_daily_fee_paid(
  p_driver_id uuid,
  p_day date default current_date
)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if public.driver_daily_fee_balance(p_driver_id, p_day) = 0 then
    return true;
  end if;

  if p_day = current_date and exists (
    select 1 from public.driver_free_day_credits
    where driver_id = p_driver_id and balance > 0
  ) then
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.driver_daily_fee_paid(uuid, date) to authenticated;

-- Rewritten from 0032_commission_free_days.sql's version, which read the
-- flat app_settings.driver_daily_fee column and relied on the
-- driver_daily_fees unique(driver_id, fee_date) constraint - both gone.
-- Spending a credit is a full-day waiver (same as a dispatcher waiving by
-- hand), not a per-tier top-up: one credit clears whatever's owed for the
-- whole day, regardless of tier.
create or replace function public.claim_free_day_credit(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text;
begin
  if public.driver_daily_fee_balance(p_driver_id) = 0 then
    return true;
  end if;

  update public.driver_free_day_credits
  set balance = balance - 1, updated_at = now()
  where driver_id = p_driver_id and balance > 0;

  if not found then
    return false;
  end if;

  select currency into v_currency from public.app_settings limit 1;

  insert into public.driver_daily_fees (
    driver_id, fee_date, amount, currency, status, payment_method, paid_at
  )
  values (
    p_driver_id, current_date, public.driver_daily_fee_amount(p_driver_id),
    coalesce(v_currency, 'GHS'), 'waived', 'free_day_credit', now()
  );

  return true;
end;
$$;

grant execute on function public.claim_free_day_credit(uuid) to authenticated;

-- A driver submits their own MoMo transaction reference for whatever
-- they currently owe (their tier amount, minus anything already paid
-- today). Updates an existing pending manual-payment row for today if one
-- exists (correcting a typo'd reference before it's reviewed), otherwise
-- inserts a new one - a driver can end up with more than one paid row in
-- a day now, but never more than one *pending* manual one at a time.
create or replace function public.submit_manual_daily_fee_payment(p_reference text)
returns public.driver_daily_fees
language plpgsql
security definer
set search_path = public
as $$
declare
  balance numeric;
  v_currency text;
  caller_role public.user_role;
  existing_id uuid;
  result public.driver_daily_fees;
begin
  select role into caller_role from public.profiles where id = auth.uid();
  if caller_role is distinct from 'driver' then
    raise exception 'Only a driver can submit their own daily fee payment.';
  end if;

  if p_reference is null or length(trim(p_reference)) = 0 then
    raise exception 'Enter the Mobile Money transaction reference.';
  end if;

  balance := public.driver_daily_fee_balance(auth.uid());
  if balance <= 0 then
    raise exception 'You have already paid today''s fee.';
  end if;

  select currency into v_currency from public.app_settings limit 1;

  select id into existing_id
  from public.driver_daily_fees
  where driver_id = auth.uid()
    and fee_date = current_date
    and status = 'pending'
    and payment_method = 'manual'
  limit 1;

  if existing_id is not null then
    update public.driver_daily_fees
    set manual_reference = trim(p_reference),
        amount = balance,
        currency = coalesce(v_currency, 'GHS')
    where id = existing_id
    returning * into result;
  else
    insert into public.driver_daily_fees (
      driver_id, fee_date, amount, currency, status, payment_method, manual_reference
    )
    values (
      auth.uid(), current_date, balance, coalesce(v_currency, 'GHS'), 'pending', 'manual', trim(p_reference)
    )
    returning * into result;
  end if;

  return result;
end;
$$;

-- A dispatcher/super admin clears [p_driver_id] for [p_day] without them
-- paying anything - a full waiver for the day regardless of tier (see
-- driver_daily_fee_balance()'s waived check above). No-ops if already
-- waived; amount recorded is whatever their tier owed at the moment of
-- waiving, purely for reporting.
create or replace function public.waive_daily_fee(
  p_driver_id uuid,
  p_day date default current_date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text;
begin
  if not public.is_dispatcher_or_above() then
    raise exception 'Only a dispatcher or super admin can waive a driver''s daily fee.';
  end if;

  if exists (
    select 1 from public.driver_daily_fees
    where driver_id = p_driver_id and fee_date = p_day and status = 'waived'
  ) then
    return;
  end if;

  select currency into v_currency from public.app_settings limit 1;

  insert into public.driver_daily_fees (
    driver_id, fee_date, amount, currency, status, confirmed_by, paid_at
  )
  values (
    p_driver_id, p_day, public.driver_daily_fee_amount(p_driver_id, p_day),
    coalesce(v_currency, 'GHS'), 'waived', auth.uid(), now()
  );
end;
$$;
