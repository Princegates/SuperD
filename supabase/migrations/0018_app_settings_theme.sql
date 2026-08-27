-- SuperD: adds the selected UI theme to app_settings, alongside currency.
-- Same singleton row as 0017_app_settings.sql; same RLS already covers it
-- (any signed-in user can read, only a super admin can update).

alter table public.app_settings
  add column if not exists theme text not null default 'navy_gold';
