-- SuperD: adds a fourth role, "auditor" - full read access to everything a
-- super admin sees (Team, Overview, Reports, Finance, Audit log,
-- Onboarding, Zones, Settings included), plus the same day-to-day dispatch
-- write access a dispatcher already has (assign drivers, update delivery
-- status, record payments), but blocked from admin-level changes: Settings,
-- Team, Zones, pricing/commission rate config, and driver notices. See
-- 0054_auditor_role_permissions.sql for what actually enforces that split.
--
-- RUN THIS FILE ON ITS OWN, LET IT FINISH, THEN RUN 0054 SEPARATELY.
-- Postgres refuses to use a brand-new enum value inside the same
-- transaction that added it ("unsafe use of new value ... must be
-- committed before it can be used") - the Supabase SQL Editor sends
-- everything pasted in one go as a single transaction, so 0054 referencing
-- 'auditor' has to be a separate paste, run after this one has committed.

alter type public.user_role add value if not exists 'auditor';
