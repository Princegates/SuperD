-- SuperD: date of birth + residential address for staff profiles.
-- Required in the app's Add/Edit forms for dispatchers; residential
-- address is also now collected for drivers (date of birth is not).

alter table public.profiles
  add column if not exists date_of_birth date,
  add column if not exists residential_address text;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, phone, ghana_card_number, vehicle_number,
    must_change_password, date_of_birth, residential_address
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
    new.raw_user_meta_data ->> 'residential_address'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
