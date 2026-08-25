-- SuperD: let a super admin add/edit/remove dispatcher accounts, the same
-- way dispatchers/super admins already manage driver accounts.

-- A super admin may also remove a dispatcher's profile row (safety-net
-- policy, same idea as the existing driver-delete one - the primary path is
-- the "admin-delete-driver" Edge Function, which cascades from auth.users).
drop policy if exists "profiles: super admin deletes dispatchers" on public.profiles;
create policy "profiles: super admin deletes dispatchers"
  on public.profiles for delete
  using (public.is_super_admin() and role = 'dispatcher');

-- Let the Edge Functions (which run with the service-role key, and have
-- already checked the human caller is authorized before ever reaching this
-- point) set a newly-created account's role to dispatcher. auth.role()
-- reflects the *cryptographically verified* JWT role claim - only Supabase
-- code holding the real service-role key can present as 'service_role', so
-- this can't be spoofed by a client. Everything else about the guard is
-- unchanged: a dispatcher, driver, or anonymous caller still can't touch
-- anyone's role.
create or replace function public.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and not public.is_super_admin()
     and auth.role() is distinct from 'service_role' then
    new.role := old.role;
  end if;
  return new;
end;
$$;
