-- SuperD: an emergency escape hatch for when the Mobile Money payment
-- gateway is down (or otherwise impractical in the moment) and a driver
-- is stuck blocked from new deliveries by either hard-block mechanism -
-- an unpaid daily-fee tier (0037_tiered_daily_fee.sql) or overdue
-- commission (0067_daily_commission_settlement.sql). A dispatcher/super
-- admin can now grant that driver temporary access anyway, without
-- touching what they actually owe: `driver_daily_fee_balance()` and
-- `driver_commission_due_amount()` are both untouched, so the debt still
-- has to be settled afterward the same ways it always could - the
-- driver's own in-app payment once the gateway's back, a manually
-- submitted reference, or in person.
--
-- Deliberately NOT the same as waive_daily_fee()/marking a commission row
-- "waived" - those forgive the debt outright. This only lifts the access
-- block for a while, on the understanding it still gets collected.
--
-- Granting/revoking is a plain `profiles` table update (like the existing
-- `daily_fee_tier_override_id` in 0038_daily_fee_tier_overrides.sql) -
-- already covered by "profiles: user updates own non-role fields" in
-- 0054_auditor_role_permissions.sql (dispatcher-or-above may write a
-- driver's row; a super-admin-only write was never needed here, same as
-- freezing/unfreezing a driver already isn't).

alter table public.profiles
  add column if not exists payment_access_override_until timestamptz;

comment on column public.profiles.payment_access_override_until is 'A dispatcher/super admin-granted temporary bypass of the daily-fee/commission access block - null means no override active. While now() is before this, driver_daily_fee_paid()/claim_free_day_credit()/driver_has_overdue_commission() all treat the driver as clear, without changing driver_daily_fee_balance()/driver_commission_due_amount() (what they actually owe, and what a payment actually charges) - meant for a payment-gateway outage where the normal or manual-reference payment flow is impractical right now.';

-- Same body as 0037_tiered_daily_fee.sql's version, plus the new override
-- check at the top.
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
  if exists (
    select 1 from public.profiles
    where id = p_driver_id and payment_access_override_until > now()
  ) then
    return true;
  end if;

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

-- Same body as 0037_tiered_daily_fee.sql's version, plus the same
-- override check - honored without spending a free-day credit, since
-- there's nothing to "claim": the debt is still there, just not blocking
-- for now.
create or replace function public.claim_free_day_credit(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text;
begin
  if exists (
    select 1 from public.profiles
    where id = p_driver_id and payment_access_override_until > now()
  ) then
    return true;
  end if;

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

-- Same body as 0067_daily_commission_settlement.sql's version, plus the
-- same override check.
create or replace function public.driver_has_overdue_commission(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  enabled boolean;
begin
  if exists (
    select 1 from public.profiles
    where id = p_driver_id and payment_access_override_until > now()
  ) then
    return false;
  end if;

  select driver_commission_enabled into enabled from public.app_settings limit 1;
  if not coalesce(enabled, true) then
    return false;
  end if;

  return exists (
    select 1 from public.commission_payments
    where driver_id = p_driver_id
      and status = 'due'
      and created_at::date < current_date
  );
end;
$$;
