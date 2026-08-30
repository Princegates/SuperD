-- SuperD: a driver must now supply their date of birth, driving licence
-- (number + expiry), and vehicle insurance (policy number + expiry) - on
-- top of the name/email/phone/vehicle already required. date_of_birth
-- already existed as a column (dispatchers only, until now); the licence
-- and insurance fields are new. All four stay nullable at the database
-- level - existing driver rows predate this and can't be backfilled with
-- real data - "required" is enforced where account creation actually
-- happens: the driver signup screen's own form validation, and
-- admin-create-driver's server-side check for an admin-created one (see
-- both files for the actual enforcement).

alter table public.profiles
  add column if not exists driving_license_number text,
  add column if not exists driving_license_expiry date,
  add column if not exists vehicle_insurance_number text,
  add column if not exists vehicle_insurance_expiry date;

comment on column public.profiles.driving_license_number is 'Driver-only - their Ghana driving licence number. Distinct from ghana_card_number (national ID), which stays optional.';
comment on column public.profiles.driving_license_expiry is 'Driver-only - when the driving licence on file expires. Required to be a future date at signup/creation time (checked in the app, not a database constraint), but not re-checked automatically once it''s on file.';
comment on column public.profiles.vehicle_insurance_number is 'Driver-only - their vehicle insurance policy number.';
comment on column public.profiles.vehicle_insurance_expiry is 'Driver-only - when the vehicle insurance policy on file expires. Same future-date check as driving_license_expiry at the point it''s entered.';

-- Same body as 0025_driver_categories_and_status.sql's version, plus the
-- four new fields - date_of_birth was already read here for a
-- dispatcher's own signup path, now also relied on for a driver's.
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
    vehicle_insurance_number, vehicle_insurance_expiry
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
    nullif(new.raw_user_meta_data ->> 'vehicle_insurance_expiry', '')::date
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
