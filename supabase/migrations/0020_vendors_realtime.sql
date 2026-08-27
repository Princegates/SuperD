-- SuperD: live-updates vendors, so a dispatcher/super admin's dashboard
-- can show an in-app notification the moment a new vendor registers -
-- same pattern as 0006_profiles_realtime.sql.

alter publication supabase_realtime add table public.vendors;
