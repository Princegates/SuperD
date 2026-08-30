-- SuperD: driver self-signup (0014_driver_self_signup.sql) goes straight
-- through Supabase's own auth.signUp() - unlike the two anonymous public
-- forms (submit_delivery_request()/register_vendor()), there's no RPC of
-- ours in front of it to rate-limit, and no caller IP available either.
-- The one piece of the request we do have and can throttle by is the
-- phone number the form already requires - same reasoning and the same
-- limit as register_vendor()'s per-phone throttle in
-- 0058_public_form_rate_limiting.sql: signing up as a driver is rarer and
-- higher-stakes than placing one order, so 3 attempts per phone number
-- per day is generous for a real person (who might mistype something and
-- need to retry) while still stopping a burst of junk signups from one
-- number. Doesn't stop a determined attacker rotating phone numbers per
-- attempt - same caveat this app's other public-form throttles already
-- carry, and a real CAPTCHA can't run here anyway: Cloudflare Turnstile
-- (already used on the two anonymous web forms) is a browser-only
-- widget, and driver self-signup only exists on the native app, which
-- never renders it.

create table if not exists public.driver_signup_attempts (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  attempted_at timestamptz not null default now()
);

create index if not exists driver_signup_attempts_phone_idx
  on public.driver_signup_attempts (phone, attempted_at desc);

comment on table public.driver_signup_attempts is 'One row per driver self-signup attempt, keyed by the phone number the form requires - backs check_driver_signup_throttle()/enforce_driver_signup_throttle() below. Not readable or writable directly by anon/authenticated; only those two security-definer functions touch it.';

alter table public.driver_signup_attempts enable row level security;

-- Called by the driver signup screen right before it calls
-- auth.signUp() - anon-callable, since nobody's authenticated yet at
-- that point. Records the attempt and raises a plain, readable exception
-- once the limit's hit for that phone number, surfaced to the driver
-- exactly like any other form error in this app. This is what makes the
-- common case friendly - the trigger below is a real backstop, but a
-- trigger's exception message reaches the client filtered through
-- Supabase's own generic "Database error saving new user" wrapping, not
-- verbatim.
create or replace function public.check_driver_signup_throttle(p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_count integer;
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'Enter your telephone number.';
  end if;

  select count(*) into recent_count
  from public.driver_signup_attempts
  where phone = p_phone and attempted_at > now() - interval '24 hours';

  if recent_count >= 3 then
    raise exception 'Too many sign-up attempts with this phone number today. Please try again tomorrow, or contact support.';
  end if;

  insert into public.driver_signup_attempts (phone) values (p_phone);
end;
$$;

grant execute on function public.check_driver_signup_throttle(text) to anon, authenticated;

-- The real, unbypassable backstop - fires on every insert into
-- auth.users no matter how it got there (the app calling signUp()
-- normally, or anyone skipping the app entirely and calling Supabase's
-- own auth API directly). Read-only against driver_signup_attempts (the
-- function above already recorded this attempt moments earlier in the
-- normal flow) - counts, never inserts, so the two never double up.
-- Skipped entirely for an admin-created account (created_by_admin in
-- raw_app_meta_data, set server-side only by the admin-create-driver
-- Edge Function - see 0014_driver_self_signup.sql) so a dispatcher
-- adding several drivers in a row is never affected.
create or replace function public.enforce_driver_signup_throttle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  recent_count integer;
begin
  if coalesce((new.raw_app_meta_data ->> 'created_by_admin')::boolean, false) then
    return new;
  end if;

  v_phone := new.raw_user_meta_data ->> 'phone';
  if v_phone is null or length(trim(v_phone)) = 0 then
    return new;
  end if;

  select count(*) into recent_count
  from public.driver_signup_attempts
  where phone = v_phone and attempted_at > now() - interval '24 hours';

  if recent_count >= 3 then
    raise exception 'Too many sign-up attempts with this phone number today. Please try again tomorrow, or contact support.';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_driver_signup_throttle on auth.users;
create trigger enforce_driver_signup_throttle
  before insert on auth.users
  for each row
  execute function public.enforce_driver_signup_throttle();
