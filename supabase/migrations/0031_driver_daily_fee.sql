-- SuperD: a flat daily platform fee every driver owes the business,
-- separate from `commission_payments` (which is owed per completed
-- delivery). A super admin sets one app-wide amount between GHS 10 and
-- 100 (or 0 to turn the whole thing off) from Console > Settings. A
-- driver who hasn't paid today's fee cannot be given a new delivery -
-- not a soft warning, an actual database-enforced block (see the
-- enforce_delivery_update()/enforce_delivery_insert() changes below) -
-- until they pay or a dispatcher waives that day for them.
--
-- Two ways to pay, both landing in the same driver_daily_fees ledger:
--   1. Real-time Mobile Money collection via Hubtel's Receive Money API
--      (see supabase/functions/hubtel-daily-fee-charge and
--      hubtel-daily-fee-webhook) - the driver taps "Pay now", approves a
--      prompt on their phone, and Hubtel's webhook flips the row to paid.
--   2. Manual confirm - the driver pays the business's MoMo number
--      directly (outside the app) and submits the transaction reference;
--      a dispatcher/super admin checks it against their MoMo statement
--      and approves or rejects it from Console > Daily Fees. This needs
--      no payment-gateway account and works as a fallback if Hubtel
--      isn't configured yet, or its webhook is ever delayed/down.
--
-- "Today" is `current_date` - Africa/Accra has no DST and sits at UTC+0
-- year-round, so the database's own (UTC) calendar day already matches
-- Ghana's local calendar day with no conversion needed.

alter table public.app_settings
  add column if not exists driver_daily_fee numeric(10, 2) not null default 0;

alter table public.app_settings
  drop constraint if exists app_settings_driver_daily_fee_check,
  add constraint app_settings_driver_daily_fee_check
    check (driver_daily_fee = 0 or (driver_daily_fee between 10 and 100));

comment on column public.app_settings.driver_daily_fee is 'Flat daily platform fee every driver owes, collected via Mobile Money. 0 = off (no driver is blocked). Otherwise must be between 10 and 100 (GHS or whatever app_settings.currency is).';

create table if not exists public.driver_daily_fees (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles (id) on delete cascade,
  fee_date date not null default current_date,
  amount numeric(10, 2) not null,
  currency text not null default 'GHS',
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'waived')),
  payment_method text check (payment_method in ('hubtel_momo', 'manual')),
  hubtel_client_reference text unique,
  hubtel_transaction_id text,
  manual_reference text,
  confirmed_by uuid references public.profiles (id),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  unique (driver_id, fee_date)
);

comment on table public.driver_daily_fees is 'One row per driver per calendar day they attempted or completed payment for - no row at all means unpaid/not yet attempted (see driver_daily_fee_paid()). Never proactively created for every driver every day; created lazily the moment a driver initiates payment, or a dispatcher waives that day for them.';

create index if not exists driver_daily_fees_driver_idx on public.driver_daily_fees (driver_id);
create index if not exists driver_daily_fees_date_idx on public.driver_daily_fees (fee_date);
create index if not exists driver_daily_fees_status_idx on public.driver_daily_fees (status);

alter table public.driver_daily_fees enable row level security;

drop policy if exists "driver_daily_fees: driver reads own" on public.driver_daily_fees;
create policy "driver_daily_fees: driver reads own"
  on public.driver_daily_fees for select
  using (driver_id = auth.uid());

drop policy if exists "driver_daily_fees: dispatcher reads all" on public.driver_daily_fees;
create policy "driver_daily_fees: dispatcher reads all"
  on public.driver_daily_fees for select
  using (public.is_dispatcher_or_above());

-- No insert/update policy for anyone - every write goes through one of
-- the SECURITY DEFINER functions below, which run as the table owner and
-- apply their own, narrower checks (never trusting a client-supplied
-- amount or driver id).

alter publication supabase_realtime add table public.driver_daily_fees;

-- Whether [p_driver_id] is clear to be assigned deliveries on [p_day]:
-- either the whole feature is off (0 = no fee configured), or they have a
-- paid/waived row for that day. SECURITY DEFINER + STABLE so it can be
-- called from RLS-restricted contexts (the enforce_delivery_* triggers,
-- and directly by an authenticated driver checking their own status)
-- without needing its own select policy.
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

  return exists (
    select 1 from public.driver_daily_fees
    where driver_id = p_driver_id
      and fee_date = p_day
      and status in ('paid', 'waived')
  );
end;
$$;

grant execute on function public.driver_daily_fee_paid(uuid, date) to authenticated;

-- Every driver who still owes today's fee - used by the Console's driver
-- picker to steer a dispatcher away from a manual assignment the
-- database would reject anyway (see the trigger changes below).
create or replace function public.unpaid_driver_ids_today()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select p.id
  from public.profiles p
  where p.role = 'driver'
    and not public.driver_daily_fee_paid(p.id);
$$;

grant execute on function public.unpaid_driver_ids_today() to authenticated;

-- A driver submits their own MoMo transaction reference after paying the
-- business's number directly, outside the app. Left "pending" for a
-- dispatcher/super admin to approve or reject from Console > Daily Fees -
-- see set_daily_fee_status() below. Safe to call again to correct a typo
-- as long as today's fee isn't already paid.
create or replace function public.submit_manual_daily_fee_payment(p_reference text)
returns public.driver_daily_fees
language plpgsql
security definer
set search_path = public
as $$
declare
  fee numeric;
  v_currency text;
  caller_role public.user_role;
  result public.driver_daily_fees;
begin
  select role into caller_role from public.profiles where id = auth.uid();
  if caller_role is distinct from 'driver' then
    raise exception 'Only a driver can submit their own daily fee payment.';
  end if;

  if p_reference is null or length(trim(p_reference)) = 0 then
    raise exception 'Enter the Mobile Money transaction reference.';
  end if;

  select driver_daily_fee, currency into fee, v_currency from public.app_settings limit 1;
  if coalesce(fee, 0) = 0 then
    raise exception 'Daily fee collection is not enabled.';
  end if;

  if public.driver_daily_fee_paid(auth.uid()) then
    raise exception 'You have already paid today''s fee.';
  end if;

  insert into public.driver_daily_fees (
    driver_id, fee_date, amount, currency, status, payment_method, manual_reference
  )
  values (
    auth.uid(), current_date, fee, coalesce(v_currency, 'GHS'), 'pending', 'manual', trim(p_reference)
  )
  on conflict (driver_id, fee_date) do update
    set status = 'pending',
        payment_method = 'manual',
        manual_reference = excluded.manual_reference,
        amount = excluded.amount,
        currency = excluded.currency
    where public.driver_daily_fees.status <> 'paid'
  returning * into result;

  if result.id is null then
    raise exception 'You have already paid today''s fee.';
  end if;

  return result;
end;
$$;

grant execute on function public.submit_manual_daily_fee_payment(text) to authenticated;

-- A dispatcher/super admin approves or rejects a manually-submitted
-- payment. Rejecting sets it back to 'failed' so the driver can correct
-- and resubmit their reference.
create or replace function public.set_daily_fee_status(p_fee_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_dispatcher_or_above() then
    raise exception 'Only a dispatcher or super admin can confirm a daily fee payment.';
  end if;

  update public.driver_daily_fees
  set status = case when p_approve then 'paid' else 'failed' end,
      paid_at = case when p_approve then now() else null end,
      confirmed_by = auth.uid()
  where id = p_fee_id;

  if not found then
    raise exception 'Daily fee record not found.';
  end if;
end;
$$;

grant execute on function public.set_daily_fee_status(uuid, boolean) to authenticated;

-- Lets a dispatcher/super admin clear a driver for a given day (default
-- today) without the driver paying anything - a new driver's first free
-- day, a goodwill gesture, or an escape hatch if Hubtel is ever
-- unreachable. Amount is still recorded (from the current setting) for
-- reporting, but status is 'waived' so it never shows as collected.
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
  fee numeric;
  v_currency text;
begin
  if not public.is_dispatcher_or_above() then
    raise exception 'Only a dispatcher or super admin can waive a driver''s daily fee.';
  end if;

  select driver_daily_fee, currency into fee, v_currency from public.app_settings limit 1;

  insert into public.driver_daily_fees (
    driver_id, fee_date, amount, currency, status, confirmed_by, paid_at
  )
  values (
    p_driver_id, p_day, coalesce(fee, 0), coalesce(v_currency, 'GHS'), 'waived', auth.uid(), now()
  )
  on conflict (driver_id, fee_date) do update
    set status = 'waived',
        confirmed_by = excluded.confirmed_by,
        paid_at = excluded.paid_at;
end;
$$;

grant execute on function public.waive_daily_fee(uuid, date) to authenticated;

-- Extends the existing frozen-driver guards (0025_driver_categories_and_status.sql)
-- with the same treatment for an unpaid daily fee - both functions keep
-- everything they already did, this just adds one more thing that blocks
-- a driver from being (re)assigned.

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

  -- Same backstop for an unpaid daily fee.
  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and not public.driver_daily_fee_paid(new.assigned_driver_id)
  then
    raise exception 'That driver has not paid today''s fee yet and cannot be assigned new deliveries.';
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
     and not public.driver_daily_fee_paid(new.assigned_driver_id)
  then
    raise exception 'That driver has not paid today''s fee yet and cannot be assigned new deliveries.';
  end if;

  return new;
end;
$$;

-- submit_delivery_request's auto-assignment candidate pool also skips
-- anyone who owes today's fee - same signature as 0030's version (only
-- the body changes), so no drop/grant needed.
create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null,
  road_distance_km double precision default null,
  scheduled_at timestamptz default null
)
returns table (
  tracking_code text,
  quoted_amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vendors%rowtype;
  s public.app_settings%rowtype;
  z public.zones%rowtype;
  v_base_fare numeric;
  v_price_per_km numeric;
  new_tracking_code text;
  straight_line_km double precision;
  distance_km double precision;
  amount numeric(10, 2);
  cos_angle double precision;
  target_driver_id uuid;
  target_status public.delivery_status;
  target_assigned_at timestamptz;
  is_due_soon boolean;
begin
  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;
  if v.zone_id is not null then
    select * into z from public.zones where id = v.zone_id;
  end if;

  v_base_fare := coalesce(z.base_fare, s.base_fare, 0);
  v_price_per_km := coalesce(z.price_per_km, s.price_per_km, 0);

  if dropoff_lat is not null and dropoff_lng is not null
     and v.location_lat is not null and v.location_lng is not null then
    cos_angle := sin(radians(v.location_lat)) * sin(radians(dropoff_lat))
      + cos(radians(v.location_lat)) * cos(radians(dropoff_lat))
        * cos(radians(dropoff_lng) - radians(v.location_lng));
    straight_line_km := 6371 * acos(least(1.0, greatest(-1.0, cos_angle)));
  else
    straight_line_km := 0;
  end if;

  distance_km := greatest(coalesce(road_distance_km, 0), straight_line_km);

  amount := least(v_base_fare + v_price_per_km * distance_km, 50);

  is_due_soon := scheduled_at is null or scheduled_at <= now() + interval '15 minutes';

  -- Pick whoever in the vendor's zone is online, active, unfrozen, and
  -- paid up on today's fee - preferring whoever already has the most
  -- active deliveries in that same zone (consolidating a zone's requests
  -- onto one driver's route), tie-broken by lightest total workload for a
  -- fair bootstrap when nobody in the zone has any yet. Skipped entirely
  -- for a delivery scheduled well into the future - see 0030.
  if v.zone_id is not null and is_due_soon then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.zone_id = v.zone_id
      and public.driver_daily_fee_paid(p.id)
    order by
      (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.zone_id = v.zone_id
          and d.status not in ('delivered', 'cancelled')
      ) desc,
      (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.status not in ('delivered', 'cancelled')
      ) asc,
      p.full_name
    limit 1;
  end if;

  if target_driver_id is not null then
    target_status := 'assigned';
    target_assigned_at := now();
  else
    target_status := 'pending';
    target_assigned_at := null;
  end if;

  insert into public.deliveries (
    customer_name, customer_phone,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    vendor_id, zone_id, created_by,
    assigned_driver_id, status, assigned_at,
    scheduled_at
  )
  values (
    customer_name, customer_phone,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, v.zone_id, null,
    target_driver_id, target_status, target_assigned_at,
    scheduled_at
  )
  returning deliveries.tracking_code into new_tracking_code;

  if amount > 0 then
    insert into public.payments (delivery_id, amount, currency)
    select id, amount, coalesce(s.currency, 'GHS')
    from public.deliveries
    where deliveries.tracking_code = new_tracking_code;
  end if;

  return query select new_tracking_code, amount, coalesce(s.currency, 'GHS');
end;
$$;
