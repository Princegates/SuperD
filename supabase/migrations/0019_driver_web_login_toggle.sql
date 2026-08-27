-- SuperD: lets a super admin temporarily allow driver accounts to sign in
-- on the web dashboard - useful for testing the driver experience (accept
-- delivery, live location, etc.) before the native Android/iOS apps are
-- built and distributed. Defaults to false (the original behavior: a
-- driver signing in on web gets signed straight back out - see
-- app_router.dart).

alter table public.app_settings
  add column if not exists allow_driver_web_login boolean not null default false;
