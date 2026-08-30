-- SuperD: push notification groundwork. One row per signed-in device's
-- FCM registration token - kept current by the app itself (upserted on
-- launch and whenever Firebase rotates the token, removed on sign-out),
-- keyed by the token rather than by profile so a device that switches
-- which staff/driver account is signed into it (a shared dispatch
-- tablet, a driver's phone handed to another driver) automatically
-- moves the token to whoever's actually signed in now instead of
-- accumulating stale rows.
--
-- Sending a push is a server-side concern (an Edge Function holding the
-- Firebase service account credentials - see the README's "Push
-- notifications" section) - this table only needs to let a signed-in
-- user manage their own device's row; there's no reason a client ever
-- needs to read anyone's tokens, its own included.

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.device_push_tokens is 'FCM registration tokens for push notifications - one row per device, upserted on token (see the app''s PushNotificationService) so a device that changes which account is signed in moves with it rather than leaving a stale row behind.';

create index if not exists device_push_tokens_profile_idx on public.device_push_tokens (profile_id);

alter table public.device_push_tokens enable row level security;

drop policy if exists "device_push_tokens: own device only" on public.device_push_tokens;
create policy "device_push_tokens: own device only"
  on public.device_push_tokens for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- Reuses the same set_updated_at() trigger function every other
-- updated_at column in this schema uses - see 0001_init.sql.
drop trigger if exists device_push_tokens_set_updated_at on public.device_push_tokens;
create trigger device_push_tokens_set_updated_at
  before update on public.device_push_tokens
  for each row execute function public.set_updated_at();
