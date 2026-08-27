-- SuperD: live driver location, for a dispatcher/super-admin "Live Map"
-- view of where drivers currently are.
--
-- No new RLS policy needed - "profiles: user updates own non-role fields"
-- (0002_roles_step2_policies.sql) already lets a driver update any column
-- on their own row, and profiles is already in the realtime publication
-- (0006_profiles_realtime.sql), so a dispatcher/super-admin's live map
-- subscription picks up every update automatically.

alter table public.profiles
  add column if not exists last_lat double precision,
  add column if not exists last_lng double precision,
  add column if not exists location_updated_at timestamptz;
