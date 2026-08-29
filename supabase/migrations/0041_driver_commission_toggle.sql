-- SuperD: a single master switch to turn driver commission off entirely
-- while testing, without losing any configuration - the per-delivery flat
-- fee (app_settings.commission_flat_fee) and the tiered daily fee
-- (driver_daily_fee_tiers) are left exactly as set, they just stop being
-- charged, tracked, or enforced while this is off. A super admin flips it
-- back on once the app is ready to go commercial. Defaults to on so
-- nothing changes for a project already relying on either mechanism.

alter table public.app_settings
  add column if not exists driver_commission_enabled boolean not null default true;

comment on column public.app_settings.driver_commission_enabled is 'Master off-switch for driver commission (both the per-delivery flat fee and the tiered daily fee). Off = nothing is charged, logged, or blocks driver assignment, but commission_flat_fee/driver_daily_fee_tiers stay untouched for when it''s turned back on.';

-- Per-delivery flat commission: skip logging a "due" record while
-- disabled, regardless of what commission_flat_fee is set to.
create or replace function public.log_commission_due()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.app_settings%rowtype;
begin
  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and new.assigned_driver_id is not null
  then
    select * into s from public.app_settings limit 1;
    if coalesce(s.driver_commission_enabled, true)
       and coalesce(s.commission_flat_fee, 0) > 0
    then
      insert into public.commission_payments (
        driver_id, delivery_id, amount, currency
      )
      values (
        new.assigned_driver_id, new.id, s.commission_flat_fee,
        coalesce(s.currency, 'GHS')
      );
    end if;
  end if;
  return new;
end;
$$;

-- Tiered daily fee: 0 owed while disabled (tier override included),
-- regardless of configured tiers - cascades through
-- driver_daily_fee_balance()/_paid() and every assignment guard that
-- calls them, so a driver is never blocked for an unpaid fee while
-- commission is off. Rewritten from 0038_daily_fee_tier_overrides.sql's
-- version, which had no disabled check at all.
create or replace function public.driver_daily_fee_amount(
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
  enabled boolean;
  override_amount numeric;
begin
  select driver_commission_enabled into enabled from public.app_settings limit 1;
  if not coalesce(enabled, true) then
    return 0;
  end if;

  select t.amount into override_amount
  from public.profiles p
  join public.driver_daily_fee_tiers t on t.id = p.daily_fee_tier_override_id
  where p.id = p_driver_id;

  if override_amount is not null then
    return override_amount;
  end if;

  return coalesce(
    (
      select t.amount
      from public.driver_daily_fee_tiers t
      where t.min_deliveries <= public.driver_completed_deliveries_on(p_driver_id, p_day)
      order by t.min_deliveries desc
      limit 1
    ),
    0
  );
end;
$$;

grant execute on function public.driver_daily_fee_amount(uuid, date) to authenticated;
