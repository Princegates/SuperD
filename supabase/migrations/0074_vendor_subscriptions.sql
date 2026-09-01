-- SuperD: a one-time vendor "activation" fee, gated by a master switch a
-- super admin controls from Console > Settings - off by default, so a
-- public vendor self-signup stays free and instantly active exactly like
-- today until a super admin turns this on and sets a fee. Once it's on,
-- a vendor who registers through the PUBLIC self-signup form (not one a
-- dispatcher/super admin adds directly from the Console - that's already
-- a vetted relationship, see the created_by check in register_vendor()
-- below) starts inactive until they pay the fee via Mobile Money, right
-- there on the signup page. This is a soft gate, not a hard block: a
-- super admin can still activate a pending vendor by hand at any time
-- from Console > Vendors (the same toggle already used for any other
-- deactivated vendor) regardless of payment - Console > Vendors just
-- shows a "Payment pending" badge so it's obvious which ones are waiting.

alter table public.app_settings
  add column if not exists vendor_subscription_enabled boolean not null default false;
alter table public.app_settings
  add column if not exists vendor_subscription_fee numeric not null default 0;

comment on column public.app_settings.vendor_subscription_enabled is 'Master switch - when true (and vendor_subscription_fee > 0), a new PUBLIC vendor self-signup starts inactive pending this one-time fee. Off by default; a vendor an admin adds directly from the Console is never gated by this, regardless of its value.';
comment on column public.app_settings.vendor_subscription_fee is 'The one-time fee charged at public vendor signup while vendor_subscription_enabled is true. Changing it only affects new registrations going forward - see vendors.subscription_fee_amount for what an existing vendor actually owed/paid.';

alter table public.vendors
  add column if not exists subscription_fee_amount numeric;
alter table public.vendors
  add column if not exists subscription_payment_reference text;
alter table public.vendors
  add column if not exists subscription_paid_at timestamptz;

comment on column public.vendors.subscription_fee_amount is 'The one-time registration fee this vendor actually owed, captured at signup time (so a later app_settings.vendor_subscription_fee change never retroactively changes it). Null means no fee applied when they registered - either the switch was off, or an admin added them directly.';
comment on column public.vendors.subscription_payment_reference is 'Paystack charge reference for the one-time fee, set the moment a charge attempt starts (see paystack-vendor-subscription-charge) - whether it actually cleared is subscription_paid_at, not this column alone.';
comment on column public.vendors.subscription_paid_at is 'When the one-time fee cleared, confirmed by Paystack''s webhook. Null while pending (is_active false, subscription_fee_amount not null) or when no fee ever applied.';

-- Looks up what the vendor behind [p_code] owes on their pending
-- subscription fee, rate-limits the attempt, and hands back what
-- paystack-vendor-subscription-charge needs to start the Mobile Money
-- charge - the amount is always read from here, never trusted from the
-- client. Raises if the vendor isn't in a chargeable state (already
-- paid/active, no fee ever applied, or the feature's since been turned
-- off) so the Edge Function doesn't have to duplicate that logic.
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
      coalesce((select currency from public.app_settings limit 1), 'GHS');
end;
$$;

-- register_vendor(): same body as 0072_permission_overrides.sql's
-- version, plus gating a public self-signup's is_active on the
-- subscription switch/fee (an admin-created vendor - created_by is not
-- null - is never gated, per the header comment above) and returning
-- is_active so the signup screen knows whether to show a payment step.
-- The output columns grow by one (is_active) here, and CREATE OR REPLACE
-- FUNCTION can't change a function's return type - it has to be dropped
-- first, or this migration fails outright with "cannot change return
-- type of existing function".
drop function if exists public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid, text
);

create or replace function public.register_vendor(
  vendor_name text,
  zone_id uuid,
  location_lat double precision,
  location_lng double precision,
  phone text,
  email text default null,
  created_by uuid default null,
  p_client_ip text default null
)
returns table (
  code text,
  orders_code text,
  is_active boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  new_orders_code text;
  subscription_required boolean;
  fee numeric;
  new_is_active boolean;
begin
  if auth.uid() is not null and not public.has_permission(auth.uid(), 'manage_vendors') then
    raise exception 'You do not have permission to add a vendor.';
  end if;

  perform public.enforce_rate_limit(
    'phone:' || phone, 'register_vendor', 3, interval '1 day'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'register_vendor', 10, interval '1 day'
  );

  select vendor_subscription_enabled, vendor_subscription_fee
    into subscription_required, fee
  from public.app_settings limit 1;

  subscription_required := coalesce(subscription_required, false)
    and created_by is null
    and coalesce(fee, 0) > 0;
  new_is_active := not subscription_required;

  loop
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    new_orders_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    begin
      insert into public.vendors (
        code, orders_code, vendor_name, zone_id, location_lat, location_lng,
        phone, email, created_by, is_active, subscription_fee_amount
      )
      values (
        new_code, new_orders_code, vendor_name, zone_id, location_lat,
        location_lng, phone, email, created_by, new_is_active,
        case when subscription_required then fee else null end
      );
      exit;
    exception when unique_violation then
      -- Vanishingly unlikely with 10/12-character codes - just try again.
    end;
  end loop;
  return query select new_code, new_orders_code, new_is_active;
end;
$$;

grant execute on function public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid, text
) to authenticated;

-- get_vendor_by_code(): same body as 0010_vendors_zones.sql's version,
-- plus the fee amount a pending vendor owes (captured on their own row
-- at signup, not re-read from app_settings) so the signup page's payment
-- step can show it - a vendor has no session at all, so it can't read
-- app_settings directly (that table's own RLS is authenticated-only).
-- Same return-type-change issue as register_vendor above (two new output
-- columns), so this also needs an explicit drop first.
drop function if exists public.get_vendor_by_code(text);

create or replace function public.get_vendor_by_code(p_code text)
returns table (
  id uuid,
  vendor_name text,
  zone_name text,
  location_lat double precision,
  location_lng double precision,
  is_active boolean,
  subscription_fee_amount numeric,
  currency text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    v.id, v.vendor_name, z.name as zone_name, v.location_lat, v.location_lng,
    v.is_active, v.subscription_fee_amount,
    coalesce((select currency from public.app_settings limit 1), 'GHS')
  from public.vendors v
  left join public.zones z on z.id = v.zone_id
  where v.code = p_code;
$$;

grant execute on function public.get_vendor_by_code(text) to anon, authenticated;
