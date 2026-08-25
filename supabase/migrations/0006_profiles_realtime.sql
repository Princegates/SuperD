-- SuperD: profiles was never added to the realtime publication, so a
-- signed-in user's own profile stream (currentProfileProvider) never
-- noticed a row changed elsewhere - e.g. must_change_password being
-- cleared, or a super admin promoting/demoting someone. It only ever saw
-- fresh data when a brand new subscription started (sign-in). This fixes
-- that for real-time role changes and password-flag clearing alike.
alter publication supabase_realtime add table public.profiles;
