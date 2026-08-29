-- SuperD: bundles a driver's outstanding per-delivery commission
-- (`commission_payments` - historically dispatcher-collected in person,
-- see `0029_commission_payments.sql`) into the SAME balance the daily-fee
-- payment flow charges and settles (`driver_daily_fee_balance()` in
-- `0037_tiered_daily_fee.sql`) - so paying "today's commission" in the
-- driver app (Mobile Money or a manual reference) also clears any
-- per-delivery commission still due, in the one payment.
--
-- The per-delivery ledger itself is untouched otherwise: it's still its
-- own count/history (see the driver's "My earnings" screen and Console >
-- Commission), a dispatcher can still mark a row paid/waived by hand, and
-- this does NOT change what blocks a driver from being assigned a new
-- delivery - `driver_daily_fee_paid()` keeps checking only the tiered
-- fee, same as before. Unpaid per-delivery commission still isn't a hard
-- block on its own; it just now rides along with whatever daily-fee
-- payment the driver already needs to make.

-- Everything currently due across the driver's per-delivery commission
-- rows - 0 while the master commission switch is off, matching
-- `driver_daily_fee_amount()`'s own guard in `0041_driver_commission_toggle.sql`.
create or replace function public.driver_commission_due_amount(p_driver_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  enabled boolean;
begin
  select driver_commission_enabled into enabled from public.app_settings limit 1;
  if not coalesce(enabled, true) then
    return 0;
  end if;

  return coalesce(
    (
      select sum(amount) from public.commission_payments
      where driver_id = p_driver_id and status = 'due'
    ),
    0
  );
end;
$$;

grant execute on function public.driver_commission_due_amount(uuid) to authenticated;

-- The actual amount to charge/collect from [p_driver_id] right now:
-- their tiered daily-fee balance for [p_day] plus everything they
-- currently owe in per-delivery commission. `paystack-daily-fee-charge`
-- and `submit_manual_daily_fee_payment()` below both charge this instead
-- of the bare daily-fee balance, so a driver's Mobile Money charge or
-- manual reference always covers everything they currently owe.
create or replace function public.driver_total_amount_due(
  p_driver_id uuid,
  p_day date default current_date
)
returns numeric
language sql
security definer
set search_path = public
stable
as $$
  select public.driver_daily_fee_balance(p_driver_id, p_day)
       + public.driver_commission_due_amount(p_driver_id);
$$;

grant execute on function public.driver_total_amount_due(uuid, date) to authenticated;

-- A driver submits their own MoMo transaction reference for whatever they
-- currently owe in total (daily fee + per-delivery commission), not just
-- the daily fee - only the amount charged changes from
-- `0037_tiered_daily_fee.sql`'s version, everything else is identical.
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

  balance := public.driver_total_amount_due(auth.uid());
  if balance <= 0 then
    raise exception 'You have nothing due right now.';
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

-- Approving a manually-submitted payment now also settles whatever
-- per-delivery commission that driver owed at the time - the amount
-- recorded on the driver_daily_fees row already included it (see
-- driver_total_amount_due() above), so this just keeps commission_payments
-- in sync with a payment that already covered it. Rejecting still just
-- flips the row to 'failed', same as before.
create or replace function public.set_daily_fee_status(p_fee_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid;
begin
  if not public.is_dispatcher_or_above() then
    raise exception 'Only a dispatcher or super admin can confirm a daily fee payment.';
  end if;

  update public.driver_daily_fees
  set status = case when p_approve then 'paid' else 'failed' end,
      paid_at = case when p_approve then now() else null end,
      confirmed_by = auth.uid()
  where id = p_fee_id
  returning driver_id into v_driver_id;

  if not found then
    raise exception 'Daily fee record not found.';
  end if;

  if p_approve then
    update public.commission_payments
    set status = 'paid', paid_at = now(), marked_paid_by = auth.uid()
    where driver_id = v_driver_id and status = 'due';
  end if;
end;
$$;
