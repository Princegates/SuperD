-- SuperD: "free days" - an incentive that excuses a driver from paying
-- the daily commission (0031_driver_daily_fee.sql) for a day, without
-- waiving it by hand each time. Two ways a driver earns one, both
-- landing in the same driver_free_day_credits balance:
--
--   1. Automatic - a super admin sets "every N completed deliveries"
--      (app_settings.free_day_delivery_threshold) and the system credits
--      one free day itself the moment a driver's lifetime completed-
--      delivery count crosses a multiple of N. No admin action needed.
--   2. Manual - a dispatcher/super admin grants some number of days
--      directly from Console > Daily Fees, at their own discretion (e.g.
--      looking at a driver's delivery count and deciding they've earned
--      more than the automatic rule alone would give).
--
-- A credit is spent automatically and transparently the moment it's
-- needed - see claim_free_day_credit() below - the driver never has to
-- ask for it to be applied. It's a genuinely separate table from
-- `profiles` (rather than a column there) so it needs no changes to the
-- existing "users update their own profile" RLS policy/guard trigger:
-- nobody gets an update policy on it at all, only the SECURITY DEFINER
-- functions here ever touch it.

create table if not exists public.driver_free_day_credits (
  driver_id uuid primary key references public.profiles (id) on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

comment on table public.driver_free_day_credits is 'How many days of commission a driver has banked as an incentive reward, not yet spent - see claim_free_day_credit(). Never updated directly by a client; only through the functions in this file.';

alter table public.driver_free_day_credits enable row level security;

drop policy if exists "driver_free_day_credits: driver reads own" on public.driver_free_day_credits;
create policy "driver_free_day_credits: driver reads own"
  on public.driver_free_day_credits for select
  using (driver_id = auth.uid());

drop policy if exists "driver_free_day_credits: dispatcher reads all" on public.driver_free_day_credits;
create policy "driver_free_day_credits: dispatcher reads all"
  on public.driver_free_day_credits for select
  using (public.is_dispatcher_or_above());

alter publication supabase_realtime add table public.driver_free_day_credits;

alter table public.app_settings
  add column if not exists free_day_delivery_threshold integer;

alter table public.app_settings
  drop constraint if exists app_settings_free_day_delivery_threshold_check,
  add constraint app_settings_free_day_delivery_threshold_check
    check (free_day_delivery_threshold is null or free_day_delivery_threshold > 0);

comment on column public.app_settings.free_day_delivery_threshold is 'Automatic free-day rule: every this many completed deliveries earns a driver 1 free commission day. Null/unset = the automatic rule is off (manual grants from Console > Daily Fees still work either way).';

-- The one place a credit is actually spent - called from the two places
-- a driver's daily-fee standing is truly decided (the delivery-assignment
-- triggers below, so it fires exactly once per real assignment, never
-- once per candidate a query merely considers) plus proactively from the
-- driver's own dashboard load, so the reward shows up as soon as they
-- open the app rather than only once dispatch tries to assign them
-- something. Idempotent: a day already paid/waived is a no-op, and
-- running low on credits just returns false rather than erroring.
create or replace function public.claim_free_day_credit(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  fee numeric;
  v_currency text;
begin
  select driver_daily_fee, currency into fee, v_currency from public.app_settings limit 1;
  if coalesce(fee, 0) = 0 then
    return true;
  end if;

  if exists (
    select 1 from public.driver_daily_fees
    where driver_id = p_driver_id
      and fee_date = current_date
      and status in ('paid', 'waived')
  ) then
    return true;
  end if;

  update public.driver_free_day_credits
  set balance = balance - 1, updated_at = now()
  where driver_id = p_driver_id and balance > 0;

  if not found then
    return false;
  end if;

  insert into public.driver_daily_fees (
    driver_id, fee_date, amount, currency, status, payment_method, paid_at
  )
  values (
    p_driver_id, current_date, fee, coalesce(v_currency, 'GHS'), 'waived', 'free_day_credit', now()
  )
  on conflict (driver_id, fee_date) do update
    set status = 'waived',
        payment_method = 'free_day_credit',
        paid_at = now()
    where public.driver_daily_fees.status <> 'paid';

  return true;
end;
$$;

grant execute on function public.claim_free_day_credit(uuid) to authenticated;

-- Read-only eligibility check (see 0031) also counts an unspent credit as
-- "clear for today" - so a driver with one banked isn't excluded from
-- being considered for assignment in the first place. Same signature as
-- 0031's version, only the body changes.
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
declare
  fee numeric;
begin
  select driver_daily_fee into fee from public.app_settings limit 1;
  if coalesce(fee, 0) = 0 then
    return true;
  end if;

  if exists (
    select 1 from public.driver_daily_fees
    where driver_id = p_driver_id
      and fee_date = p_day
      and status in ('paid', 'waived')
  ) then
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

-- A dispatcher/super admin manually awards free days on top of whatever
-- the automatic rule gives - full discretion, e.g. based on a driver's
-- delivery count shown right alongside this in Console > Daily Fees.
create or replace function public.grant_free_day_credits(p_driver_id uuid, p_days integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_dispatcher_or_above() then
    raise exception 'Only a dispatcher or super admin can grant free days.';
  end if;
  if p_days is null or p_days <= 0 then
    raise exception 'Enter a positive number of days.';
  end if;

  insert into public.driver_free_day_credits (driver_id, balance, updated_at)
  values (p_driver_id, p_days, now())
  on conflict (driver_id) do update
    set balance = public.driver_free_day_credits.balance + p_days,
        updated_at = now();
end;
$$;

grant execute on function public.grant_free_day_credits(uuid, integer) to authenticated;

-- Automatic side: the moment a delivery is marked delivered, check
-- whether the assigned driver's lifetime completed-delivery count just
-- crossed a multiple of the configured threshold, and if so credit one
-- free day - then immediately try to apply it to today, so a driver who
-- happens to earn one while they still owe today's commission feels the
-- reward right away instead of only on their next dashboard visit.
create or replace function public.grant_free_day_credit_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  threshold integer;
  delivered_count integer;
begin
  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and new.assigned_driver_id is not null
  then
    select free_day_delivery_threshold into threshold from public.app_settings limit 1;
    if threshold is not null and threshold > 0 then
      select count(*) into delivered_count
      from public.deliveries
      where assigned_driver_id = new.assigned_driver_id
        and status = 'delivered';

      if delivered_count % threshold = 0 then
        insert into public.driver_free_day_credits (driver_id, balance, updated_at)
        values (new.assigned_driver_id, 1, now())
        on conflict (driver_id) do update
          set balance = public.driver_free_day_credits.balance + 1,
              updated_at = now();

        perform public.claim_free_day_credit(new.assigned_driver_id);
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists deliveries_grant_free_day_credit on public.deliveries;
create trigger deliveries_grant_free_day_credit
  after update on public.deliveries
  for each row execute function public.grant_free_day_credit_on_delivery();

-- The assignment guards now spend a credit (rather than just checking
-- one's available) at the one moment that's actually safe to do so - a
-- real, committed assignment to exactly one driver, not a candidate a
-- query is merely weighing. Everything else in both functions is
-- unchanged from 0031.

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
begin
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
