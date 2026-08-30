-- SuperD: a percentage-of-delivery-payment commission, on top of the
-- existing flat per-delivery fee (`app_settings.commission_flat_fee`,
-- see `0029_commission_payments.sql`) - so a super admin can charge
-- drivers e.g. "GHS 2 + 5% of the delivery's payment amount" instead of
-- only a flat number. Additive, not a replacement: either can be 0 on
-- its own without disabling the other, and `driver_commission_enabled`
-- (`0041_driver_commission_toggle.sql`) still turns both off together.

alter table public.app_settings
  add column if not exists commission_percentage numeric(5, 2) not null default 0
    check (commission_percentage >= 0 and commission_percentage <= 100);

comment on column public.app_settings.commission_percentage is 'Percentage of a completed delivery''s recorded payment amount the driver owes the business, added to commission_flat_fee to make up the single amount due row created by log_commission_due(). 0 = no percentage-based commission (flat fee, if any, still applies).';

-- Same trigger function as 0041_driver_commission_toggle.sql, now also
-- adding commission_percentage% of whatever's been recorded in
-- `payments` for this delivery (0 if nothing's been recorded yet - a
-- delivery priced entirely by hand with no payment logged only ever
-- generates the flat portion, same as before this migration existed).
create or replace function public.log_commission_due()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.app_settings%rowtype;
  v_payment_total numeric;
  v_amount numeric;
begin
  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and new.assigned_driver_id is not null
  then
    select * into s from public.app_settings limit 1;
    if coalesce(s.driver_commission_enabled, true) then
      select coalesce(sum(amount), 0) into v_payment_total
      from public.payments
      where delivery_id = new.id;

      v_amount := coalesce(s.commission_flat_fee, 0)
        + v_payment_total * coalesce(s.commission_percentage, 0) / 100;

      if v_amount > 0 then
        insert into public.commission_payments (
          driver_id, delivery_id, amount, currency
        )
        values (
          new.assigned_driver_id, new.id, v_amount,
          coalesce(s.currency, 'GHS')
        );
      end if;
    end if;
  end if;
  return new;
end;
$$;
