-- SuperD: fix the role-change guard so a direct SQL Editor / migration
-- UPDATE actually works (this is how the README's "promote your first
-- super admin" bootstrap step is meant to run).
--
-- enforce_profile_role_change() only ever let a role change through for a
-- verified super admin (auth.uid() resolving to one) or, as of the
-- previous migration, our service-role Edge Functions. A query run
-- directly in the SQL Editor goes straight to Postgres, bypassing
-- PostgREST entirely - so auth.uid() and auth.role() are both null there,
-- which matched neither allowed case and the trigger silently reverted
-- the UPDATE back to the old role (no error, so it looked like it worked).
--
-- A direct database connection (SQL Editor, migrations, psql) already has
-- unrestricted power over the database regardless of this trigger - it
-- could just as easily disable RLS or drop the trigger outright - so
-- letting it through here adds no real risk. Contrast with a request that
-- actually goes through PostgREST: an anonymous or authenticated-but-not-
-- super-admin request still can't reach this trigger for someone else's
-- row at all (auth.uid() is null or resolves to a non-admin, and either
-- way profiles' own UPDATE policy's `using (id = auth.uid() or
-- is_dispatcher_or_above())` blocks the row before the trigger ever
-- fires), and for a non-admin's *own* row the trigger still reverts as
-- before - only the "nobody's logged in at all" case changes.
create or replace function public.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and not public.is_super_admin()
     and auth.role() is distinct from 'service_role'
     and auth.uid() is not null then
    new.role := old.role;
  end if;
  return new;
end;
$$;
