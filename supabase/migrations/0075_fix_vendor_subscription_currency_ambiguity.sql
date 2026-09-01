-- Fixes a bug in charge_vendor_subscription_precheck() (added in
-- 0074_vendor_subscriptions.sql) that broke every "Pay via Mobile Money"
-- attempt in production with "column reference \"currency\" is
-- ambiguous". The function's own RETURNS TABLE output column is named
-- `currency`, and PL/pgSQL implicitly declares every OUT column as a
-- variable in scope for the whole function body - so its unqualified
-- `select currency from public.app_settings` couldn't tell whether
-- `currency` meant that variable or app_settings.currency. Only this
-- plpgsql function had the problem: get_vendor_by_code() has the exact
-- same `select currency from public.app_settings` line but is a plain
-- `language sql` function, which never turns its output columns into
-- bindable variables in the first place - that's why the fee amount
-- displayed correctly on the signup page while paying still failed.
-- Fixed by qualifying the column with its table name, same as every
-- other column reference in this function already does via `v.`.

create or replace function public.charge_vendor_subscription_precheck(
  p_code text,
  p_client_ip text default null
)
returns table (
  vendor_id uuid,
  email text,
  amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vendors%rowtype;
  enabled boolean;
begin
  select * into v from public.vendors where code = p_code;
  if not found then
    raise exception 'Vendor not found';
  end if;

  select vendor_subscription_enabled into enabled
  from public.app_settings limit 1;

  if not coalesce(enabled, false) then
    raise exception 'The subscription fee is not currently required.';
  end if;
  if v.subscription_fee_amount is null then
    raise exception 'No subscription fee applies to this vendor.';
  end if;
  if v.subscription_paid_at is not null or v.is_active then
    raise exception 'This vendor is already active.';
  end if;

  perform public.enforce_rate_limit(
    'code:' || p_code, 'vendor_subscription_charge', 5, interval '1 day'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'vendor_subscription_charge', 10, interval '1 day'
  );

  return query
    select
      v.id,
      coalesce(v.email, v.id::text || '@vendors.superd.app'),
      v.subscription_fee_amount,
      coalesce((select app_settings.currency from public.app_settings limit 1), 'GHS');
end;
$$;
