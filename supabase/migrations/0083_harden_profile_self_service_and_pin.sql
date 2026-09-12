-- SuperD: closes three ways a signed-in driver could help themselves to
-- something only staff are supposed to grant.
--
-- The `profiles: user updates own non-role fields` policy (0072's version)
-- deliberately lets anyone update their own row - that's how a driver sets
-- their online toggle, clears must_change_password after a first sign-in,
-- and edits their own contact details. enforce_profile_role_change() is
-- what stops that self-update from touching a *privileged* column, and
-- until now it only covered role, is_frozen and daily_fee_tier_override_id.
-- Three more columns needed the same treatment:
--
--   * is_active - a self-signed-up driver starts inactive, "pending
--     approval", and a dispatcher flipping this is the entire approval
--     gate (0014_driver_self_signup.sql). Unguarded, that driver could
--     approve themselves with one PostgREST call against their own row and
--     start taking real deliveries - and with them, real customers' names,
--     phone numbers and addresses.
--   * payment_access_override_until - the emergency bypass of the
--     daily-fee/commission block (0068), meant to be granted by dispatch
--     for a payment-gateway outage. Unguarded, a driver could set it years
--     out and never pay commission again while still being assigned work.
--   * zone_id - which zone a driver is rostered to, set by staff on the
--     Team/Drivers form.
--
-- Each is reverted to its old value (rather than raising) for the same
-- reason the existing three are: a driver's own legitimate profile update
-- shouldn't fail just because it round-trips a column it isn't allowed to
-- change - it just doesn't get to change it.
--
-- The authorization predicate mirrors 0072's own RLS policy for the row
-- being written, so staff who can already manage that profile keep working
-- exactly as before and only the self-service path is narrowed.
--
-- Also restores the `service_role` bypass that 0008_role_change_bootstrap
-- added and 0038_daily_fee_tier_overrides silently dropped when it last
-- rewrote this function. Without it every Edge Function running on the
-- service-role key is treated as an anonymous caller here, so
-- admin-create-driver's "promote the new account to dispatcher" update was
-- being reverted on the way through - the function reported success and
-- left a driver behind. These triggers are not the access control for
-- those functions; each one checks the caller's own role itself before it
-- writes (see admin-create-driver/index.ts).

-- True when the current caller may administer a profile row whose role is
-- [p_target_role] - the same test 0072's update/insert policies apply,
-- kept in one place so the trigger below can't drift from them.
create or replace function public.can_manage_profile(p_target_role text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when p_target_role = 'driver'
      then public.has_permission(auth.uid(), 'manage_drivers')
    else public.is_dispatcher_or_above() and not public.is_auditor()
  end;
$$;

grant execute on function public.can_manage_profile(text) to authenticated;

create or replace function public.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- An Edge Function on the service-role key has already checked the
  -- caller's role itself; auth.uid() is null there, so every helper below
  -- would otherwise read as "not allowed".
  is_service_role boolean := auth.role() = 'service_role' or auth.uid() is null;
  may_manage boolean := is_service_role or public.can_manage_profile(old.role::text);
  is_super boolean := is_service_role or public.is_super_admin();
begin
  if new.role is distinct from old.role and not is_super then
    new.role := old.role;
  end if;
  if new.is_frozen is distinct from old.is_frozen and not is_super then
    new.is_frozen := old.is_frozen;
  end if;
  if new.daily_fee_tier_override_id is distinct from old.daily_fee_tier_override_id
     and not is_super
  then
    new.daily_fee_tier_override_id := old.daily_fee_tier_override_id;
  end if;

  -- Approving/deactivating an account, granting the payment-block bypass,
  -- and rostering a driver to a zone are all staff actions - never
  -- something the account holder does to their own row.
  if new.is_active is distinct from old.is_active and not may_manage then
    new.is_active := old.is_active;
  end if;
  if new.payment_access_override_until is distinct from old.payment_access_override_until
     and not may_manage
  then
    new.payment_access_override_until := old.payment_access_override_until;
  end if;
  if new.zone_id is distinct from old.zone_id and not may_manage then
    new.zone_id := old.zone_id;
  end if;

  return new;
end;
$$;

-- Cryptographically random completion PIN, and a cap on how many times a
-- driver may guess one.
--
-- 0056_delivery_completion_pin.sql picked the PIN with random(), which is a
-- seeded PRNG, not a CSPRNG - two PINs drawn in the same session are
-- predictable from each other. gen_random_uuid() is backed by the server's
-- strong RNG, so the four digits below are drawn from that instead. Still
-- four digits: the driver's own entry dialog expects exactly four, and the
-- attempt cap added below is what actually makes the code unguessable -
-- 10,000 possibilities was never going to be enough on its own, and isn't
-- what was protecting it.
create or replace function public.generate_delivery_completion_pin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_driver_id is not null
     and (tg_op = 'INSERT' or old.assigned_driver_id is distinct from new.assigned_driver_id)
  then
    insert into public.delivery_completion_pins (delivery_id, pin)
    values (
      new.id,
      lpad(
        (
          abs(
            ('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint
          ) % 10000
        )::text,
        4,
        '0'
      )
    )
    on conflict (delivery_id) do update
      set pin = excluded.pin, created_at = now();
  end if;
  return new;
end;
$$;

-- A four-digit PIN is only 10,000 guesses, and nothing counted them: the
-- driver already assigned to a delivery could walk the whole keyspace in
-- seconds and mark it delivered without the customer ever confirming
-- receipt - the one thing this PIN exists to prove, and what both the
-- customer's payment and the driver's commission hang on.
--
-- Ten attempts per delivery per hour, keyed per driver so one driver
-- burning their attempts can't lock out another the delivery is later
-- reassigned to. Successes count too - a real handover only needs one - so
-- a correct guess can't be used to reset the counter.
--
-- The reason this returns a message instead of raising it, unlike every
-- other guard in this schema: PostgREST runs an RPC in one transaction, so
-- raising rolls the *whole* call back - including the row recording the
-- attempt. Counting failed guesses only works if the call that made one
-- still commits, so a wrong PIN has to be an ordinary return value.
-- (Verified the hard way: with `raise` here, 30 consecutive wrong guesses
-- sailed through, because each rollback undid its own counter row.)
-- Null means the delivery went through; anything else is a message meant
-- for the driver, which DeliveryRepository.completeDeliveryWithPin turns
-- back into the PostgrestException its caller already handles.
--
-- Return type changes, so this has to be dropped rather than replaced.
drop function if exists public.complete_delivery_with_pin(uuid, text);

create function public.complete_delivery_with_pin(
  p_delivery_id uuid,
  p_pin text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expected_pin text;
  v_key text := 'pin:' || p_delivery_id::text || ':'
                || coalesce(auth.uid()::text, 'anon');
  v_attempts integer;
begin
  select count(*) into v_attempts
  from public.rate_limit_hits
  where key = v_key
    and action = 'complete_delivery_with_pin'
    and created_at > now() - interval '1 hour';

  if v_attempts >= 10 then
    return 'Too many incorrect PIN attempts for this delivery. '
           || 'Wait an hour, or ask dispatch for help.';
  end if;

  insert into public.rate_limit_hits (key, action)
  values (v_key, 'complete_delivery_with_pin');

  select pin into v_expected_pin
  from public.delivery_completion_pins
  where delivery_id = p_delivery_id;

  if v_expected_pin is null then
    return 'No delivery PIN is on file for this delivery - contact dispatch.';
  end if;

  if btrim(p_pin) is distinct from v_expected_pin then
    return 'That PIN doesn''t match. Ask the customer to confirm it again.';
  end if;

  perform set_config('superd.pin_verified', 'true', true);

  update public.deliveries
  set status = 'delivered'
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status = 'picked_up';

  if not found then
    return 'This delivery cannot be marked delivered right now.';
  end if;

  delete from public.delivery_completion_pins where delivery_id = p_delivery_id;
  return null;
end;
$$;

grant execute on function public.complete_delivery_with_pin(uuid, text) to authenticated;
