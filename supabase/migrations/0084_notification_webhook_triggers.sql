-- SuperD: puts the notify-* webhook wiring in the repo, where the rest of
-- the schema lives.
--
-- Until now this existed only as steps in the README (and, on this
-- project, as hand-run SQL) - so a fresh deployment came up with the
-- Edge Functions deployed but nothing calling them, and no notification
-- ever fired. That's not a state you can see: everything looks configured,
-- the functions are green in the dashboard, and the app is simply silent.
--
-- Uses pg_net triggers rather than dashboard Database Webhooks. Both end
-- up calling net.http_post; the difference is that this one is in version
-- control and applies with the rest of the migrations, instead of being a
-- checklist someone has to remember.
--
-- ---------------------------------------------------------------------
-- THE SECRET IS NOT IN THIS FILE, and must not be.
--
-- Every notify-* function requires an x-webhook-secret header matching its
-- WEBHOOK_SECRET Edge Function secret (see _shared/webhook_auth.ts). That
-- value lives in webhook_config below - a row, not a literal - so this
-- migration is safe to commit. Set it once per environment with:
--
--   insert into public.webhook_config (secret) values ('<the secret>')
--   on conflict (id) do update set secret = excluded.secret;
--
-- Rotating it later is the same statement again; the triggers read through
-- webhook_secret() and need no changes.
-- ---------------------------------------------------------------------

create table if not exists public.webhook_config (
  -- Single-row table: the check constraint makes a second row impossible,
  -- so `on conflict (id)` is always an upsert of the one that matters.
  id boolean primary key default true check (id),
  secret text not null,
  updated_at timestamptz not null default now()
);

-- No policies, deliberately. Nothing reaches this table except the
-- security-definer functions below, which bypass RLS - so a signed-in
-- client (or a leaked anon key) can't read the secret.
alter table public.webhook_config enable row level security;

revoke all on table public.webhook_config from anon, authenticated;

-- Carry over a secret from the hand-run version of this setup, where it
-- was a literal inside webhook_secret(), so applying this migration to an
-- environment that's already working doesn't silently break it. Skipped
-- when there's nothing to carry, or when what's there is the placeholder
-- from the script that shipped before this migration existed.
do $$
declare
  existing text;
begin
  if to_regprocedure('public.webhook_secret()') is not null then
    begin
      execute 'select public.webhook_secret()' into existing;
    exception when others then
      existing := null;
    end;
  end if;

  if existing is not null
     and existing <> ''
     and existing not like 'PASTE_%'
     and existing not like 'REPLACE_%'
  then
    insert into public.webhook_config (secret) values (existing)
    on conflict (id) do update set secret = excluded.secret, updated_at = now();
  end if;
end $$;

create or replace function public.webhook_secret()
returns text
language sql
stable
security definer
set search_path = public
as $$ select secret from public.webhook_config limit 1 $$;

revoke all on function public.webhook_secret() from public, anon, authenticated;

-- One header builder so no trigger can drift from the others.
create or replace function public.webhook_headers()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'Content-Type', 'application/json',
    'x-webhook-secret', coalesce(public.webhook_secret(), '')
  );
$$;

revoke all on function public.webhook_headers() from public, anon, authenticated;

-- The project's own functions base URL. Kept beside the secret rather than
-- hardcoded per trigger, so a restore into a different project is one
-- update instead of five.
alter table public.webhook_config
  add column if not exists functions_base_url text
    not null default 'https://atpokstjgdhdcbnwrbrp.supabase.co/functions/v1';

create or replace function public.webhook_url(p_function text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rtrim(functions_base_url, '/') || '/' || p_function
  from public.webhook_config limit 1
$$;

revoke all on function public.webhook_url(text) from public, anon, authenticated;

-- ====================================================================
-- deliveries -> notify-delivery-events
--
-- Sends `type` and `old_record` as well as `record`: the function tells a
-- new assignment, a pickup and a mid-trip cancellation apart by comparing
-- the two rows, and can't do that from the new row alone.
-- ====================================================================
create or replace function public.trigger_notify_delivery_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := public.webhook_url('notify-delivery-events'),
    headers := public.webhook_headers(),
    body := jsonb_build_object(
      'type', tg_op,
      'record', to_jsonb(new),
      'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end
    ),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists notify_delivery_events on public.deliveries;
create trigger notify_delivery_events
after insert or update on public.deliveries
for each row execute function public.trigger_notify_delivery_events();

-- ====================================================================
-- profiles (insert) -> notify-driver-application
-- ====================================================================
create or replace function public.trigger_notify_driver_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := public.webhook_url('notify-driver-application'),
    headers := public.webhook_headers(),
    body := jsonb_build_object('record', to_jsonb(new)),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists notify_driver_application on public.profiles;
create trigger notify_driver_application
after insert on public.profiles
for each row execute function public.trigger_notify_driver_application();

-- ====================================================================
-- profiles (update) -> notify-driver-approved
--
-- Guarded in SQL rather than letting the function decide. Every driver
-- location ping is an update to this table, so an unguarded trigger fires
-- an HTTP request every ~15 seconds per online driver just to be told
-- there's nothing to send.
-- ====================================================================
create or replace function public.trigger_notify_driver_approved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.is_active is distinct from false or new.is_active is distinct from true then
    return new;
  end if;

  perform net.http_post(
    url := public.webhook_url('notify-driver-approved'),
    headers := public.webhook_headers(),
    body := jsonb_build_object(
      'record', to_jsonb(new),
      'old_record', to_jsonb(old)
    ),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists notify_driver_approved on public.profiles;
create trigger notify_driver_approved
after update on public.profiles
for each row execute function public.trigger_notify_driver_approved();

-- ====================================================================
-- vendors (insert) -> notify-vendor-registered
-- ====================================================================
create or replace function public.trigger_notify_vendor_registered()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := public.webhook_url('notify-vendor-registered'),
    headers := public.webhook_headers(),
    body := jsonb_build_object('record', to_jsonb(new)),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists notify_vendor_registered on public.vendors;
create trigger notify_vendor_registered
after insert on public.vendors
for each row execute function public.trigger_notify_vendor_registered();

-- ====================================================================
-- driver_notices (insert) -> notify-driver-notice
-- ====================================================================
create or replace function public.trigger_notify_driver_notice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := public.webhook_url('notify-driver-notice'),
    headers := public.webhook_headers(),
    body := jsonb_build_object('record', to_jsonb(new)),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists notify_driver_notice on public.driver_notices;
create trigger notify_driver_notice
after insert on public.driver_notices
for each row execute function public.trigger_notify_driver_notice();

-- Orphans from earlier hand-run attempts on this project: their triggers
-- were dropped but the functions outlived them.
drop function if exists public.trigger_notify_delivery_insert();
drop function if exists public.trigger_notify_delivery_update();
