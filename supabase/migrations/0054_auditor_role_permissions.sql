-- SuperD: wires up what the "auditor" role (added in
-- 0053_add_auditor_role_enum.sql) can and can't do. Run 0053 first and let
-- it commit - this file uses the literal 'auditor' enum value, which
-- Postgres refuses inside the same transaction that added it.
--
-- The design: is_dispatcher_or_above() now also returns true for an
-- auditor, so every existing policy/trigger already gated on it (deliveries,
-- vendors, payments, commission_payments, driver_daily_fees, driver roster
-- management, proof-of-delivery, etc.) automatically opens up to an auditor
-- exactly the same as a dispatcher - that's the "same day-to-day dispatch
-- work" half of the role, and needs no per-table changes below.
--
-- What's left is narrower than it might look, because most of the
-- super-admin-only Console tabs already read from tables with a wide-open
-- SELECT policy (`using (true)` for zones/zone_locations/driver_daily_fee_
-- tiers, `using (auth.uid() is not null)` for app_settings) and a WRITE
-- policy gated on is_super_admin() specifically, not is_dispatcher_or_above()
-- - an auditor was never going to satisfy is_super_admin(), so Settings,
-- Zones, and fee-tier writes are already blocked with zero changes needed.
-- Three things actually need touching:
--
--   1. audit_log's SELECT policy is_super_admin()-only - widened so an
--      auditor can view the Audit log tab (it couldn't otherwise, unlike
--      every other Console tab's backing table).
--   2. driver_notices' insert/update/delete policies are
--      is_dispatcher_or_above()-only - explicitly excludes is_auditor()
--      now, since posting/ending a notice is the one *write* action a
--      plain dispatcher has that's meant to stay off-limits to an auditor.
--   3. profiles' "user updates own non-role fields" (and the matching
--      insert policy) - restricted so an auditor inheriting
--      is_dispatcher_or_above() can still approve/edit/freeze a *driver*
--      (day-to-day roster work, unchanged), but can't touch another
--      dispatcher/super admin's account (that's "Team" management, which
--      stays admin-only). Role changes themselves were already
--      super-admin-only via enforce_profile_role_change() - untouched.

create or replace function public.is_auditor()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'auditor'
  );
$$;

create or replace function public.is_dispatcher_or_above()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('dispatcher', 'super_admin', 'auditor')
  );
$$;

-- ---------------------------------------------------------------------------
-- 1. Audit log: read access widened to include an auditor.
-- ---------------------------------------------------------------------------
drop policy if exists "audit_log: super admin reads" on public.audit_log;
create policy "audit_log: super admin or auditor reads"
  on public.audit_log for select
  using (public.is_super_admin() or public.is_auditor());

-- ---------------------------------------------------------------------------
-- 2. Driver notices: writes explicitly excluded for an auditor. Reads stay
--    on is_dispatcher_or_above() as-is (0046_driver_notices.sql) - an
--    auditor can still see what's been posted, just not post/end/delete one.
-- ---------------------------------------------------------------------------
drop policy if exists "driver_notices: dispatcher inserts" on public.driver_notices;
create policy "driver_notices: dispatcher inserts"
  on public.driver_notices for insert
  with check (public.is_dispatcher_or_above() and not public.is_auditor());

drop policy if exists "driver_notices: dispatcher updates" on public.driver_notices;
create policy "driver_notices: dispatcher updates"
  on public.driver_notices for update
  using (public.is_dispatcher_or_above() and not public.is_auditor())
  with check (public.is_dispatcher_or_above() and not public.is_auditor());

drop policy if exists "driver_notices: dispatcher deletes" on public.driver_notices;
create policy "driver_notices: dispatcher deletes"
  on public.driver_notices for delete
  using (public.is_dispatcher_or_above() and not public.is_auditor());

-- ---------------------------------------------------------------------------
-- 3. Profiles: an auditor may only write a *driver's* row (or their own),
--    never another dispatcher/super admin's - that's Team management.
-- ---------------------------------------------------------------------------
drop policy if exists "profiles: user updates own non-role fields" on public.profiles;
create policy "profiles: user updates own non-role fields"
  on public.profiles for update
  using (
    id = auth.uid()
    or (public.is_dispatcher_or_above() and (not public.is_auditor() or role = 'driver'))
  )
  with check (
    id = auth.uid()
    or (public.is_dispatcher_or_above() and (not public.is_auditor() or role = 'driver'))
  );

drop policy if exists "profiles: dispatcher inserts" on public.profiles;
create policy "profiles: dispatcher inserts"
  on public.profiles for insert
  with check (
    public.is_dispatcher_or_above()
    and (not public.is_auditor() or role = 'driver')
  );
