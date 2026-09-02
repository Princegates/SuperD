-- SuperD: records that a vendor/driver actually agreed to the Terms &
-- Privacy Policy (lib/shared/legal/superd_legal_policy.dart) at signup -
-- both the timestamp and which version of the document they saw, so a
-- later dispute or a future version bump both have a real answer to "what
-- did they actually agree to, and when". The checkbox itself is enforced
-- client-side (the signup screens won't submit until it's checked); these
-- columns are the durable proof once they do.
--
-- Nullable at the database level, same reasoning as the driver
-- license/insurance fields in 0070_driver_license_and_insurance.sql: an
-- admin-added vendor or admin-created driver account never went through
-- either signup form, so never had anything to agree to - "required" is
-- enforced where the self-service forms actually are, not here.

alter table public.profiles
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text;

alter table public.vendors
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text;

comment on column public.profiles.terms_accepted_at is 'When this driver (or dispatcher/auditor/super admin, if ever added this way) agreed to the Terms & Privacy Policy on the self-signup form - null for an admin-created account, which never showed them one.';
comment on column public.profiles.terms_version is 'kTermsVersion (lib/shared/legal/superd_legal_policy.dart) at the moment terms_accepted_at was set - lets a later policy change be told apart from what an existing account actually agreed to.';
comment on column public.vendors.terms_accepted_at is 'When this vendor agreed to the Terms & Privacy Policy on the public self-signup form - null for a vendor a dispatcher/super admin added directly from the Console, which never showed them one.';
comment on column public.vendors.terms_version is 'kTermsVersion (lib/shared/legal/superd_legal_policy.dart) at the moment terms_accepted_at was set.';

-- Same body as 0070_driver_license_and_insurance.sql's version, plus
-- picking up the two new terms fields from signup metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, phone, ghana_card_number, vehicle_number,
    vehicle_type, must_change_password, date_of_birth, residential_address,
    is_active, driving_license_number, driving_license_expiry,
    vehicle_insurance_number, vehicle_insurance_expiry,
    terms_accepted_at, terms_version
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'ghana_card_number',
    new.raw_user_meta_data ->> 'vehicle_number',
    nullif(new.raw_user_meta_data ->> 'vehicle_type', '')::public.driver_vehicle_type,
    coalesce((new.raw_user_meta_data ->> 'must_change_password')::boolean, false),
    nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date,
    new.raw_user_meta_data ->> 'residential_address',
    coalesce((new.raw_app_meta_data ->> 'created_by_admin')::boolean, false),
    new.raw_user_meta_data ->> 'driving_license_number',
    nullif(new.raw_user_meta_data ->> 'driving_license_expiry', '')::date,
    new.raw_user_meta_data ->> 'vehicle_insurance_number',
    nullif(new.raw_user_meta_data ->> 'vehicle_insurance_expiry', '')::date,
    nullif(new.raw_user_meta_data ->> 'terms_accepted_at', '')::timestamptz,
    new.raw_user_meta_data ->> 'terms_version'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Same body as 0074_vendor_subscriptions.sql's version, plus a new
-- trailing p_terms_version param, recorded on the new row. Adding a
-- parameter is a different signature to Postgres, not a replacement of
-- the existing one - see 0076_drop_stale_register_vendor_overload.sql's
-- header comment for what happens if this drop is skipped.
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
  p_client_ip text default null,
  p_terms_version text default null
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
        phone, email, created_by, is_active, subscription_fee_amount,
        terms_accepted_at, terms_version
      )
      values (
        new_code, new_orders_code, vendor_name, zone_id, location_lat,
        location_lng, phone, email, created_by, new_is_active,
        case when subscription_required then fee else null end,
        case when p_terms_version is not null then now() else null end,
        p_terms_version
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
  text, uuid, double precision, double precision, text, text, uuid, text, text
) to authenticated;
