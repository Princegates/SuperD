-- SuperD: driver profile details + dispatcher-managed driver accounts.
--
-- Lets a dispatcher/super admin add a driver's Ghana card number and
-- vehicle number, and gives them a way to delete a driver's profile row.
-- Actually creating/deleting the underlying login (auth.users row) happens
-- through the "admin-create-driver" / "admin-delete-driver" Edge Functions
-- (they need the service-role key, which never belongs in the app) - see
-- supabase/functions/ and the README.

alter table public.profiles
  add column if not exists ghana_card_number text,
  add column if not exists vehicle_number text;

-- Pick up the extra fields when the Edge Function creates the auth user
-- with them in user_metadata (self-signup just won't set these, which is
-- fine - they stay null until a dispatcher fills them in).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, phone, ghana_card_number, vehicle_number
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'ghana_card_number',
    new.raw_user_meta_data ->> 'vehicle_number'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- A dispatcher/super admin can remove a driver's profile row from the app.
-- (The matching auth.users login is deleted separately by the
-- "admin-delete-driver" Edge Function, which cascades to this table anyway -
-- this policy is a safety net, not the primary deletion path.)
drop policy if exists "profiles: dispatcher deletes drivers" on public.profiles;
create policy "profiles: dispatcher deletes drivers"
  on public.profiles for delete
  using (public.is_dispatcher_or_above() and role = 'driver');
