-- SuperD: self-service driver signup, pending approval.
--
-- Drivers can now create their own login from the native app (never the
-- web dashboard - that's enforced client-side by the router, since this is
-- a public signup endpoint either way). To keep that safe, a self-signed-up
-- driver starts INACTIVE and can't be assigned deliveries until a
-- dispatcher or super admin approves them (flips `is_active` to true from
-- the Team screen).
--
-- The signal that decides which case we're in is `raw_app_meta_data`, not
-- `raw_user_meta_data`: app_metadata can only be set server-side (with the
-- service-role key), never by the signing-up client itself. The
-- "admin-create-driver" Edge Function sets `created_by_admin: true` there
-- when a dispatcher/super admin adds someone through the Team screen, so
-- those accounts start active immediately - only the public signup path
-- (which never sets it) starts pending.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, phone, ghana_card_number, vehicle_number,
    must_change_password, date_of_birth, residential_address, is_active
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'ghana_card_number',
    new.raw_user_meta_data ->> 'vehicle_number',
    coalesce((new.raw_user_meta_data ->> 'must_change_password')::boolean, false),
    nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date,
    new.raw_user_meta_data ->> 'residential_address',
    coalesce((new.raw_app_meta_data ->> 'created_by_admin')::boolean, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
