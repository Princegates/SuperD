-- SuperD: lets a super admin pin a specific driver to a specific daily-fee
-- tier - "this driver always owes tier 2's amount" - overriding the normal
-- automatic calculation (highest tier reached by today's completed
-- delivery count) entirely for that driver, until the override is cleared.
-- Same "super-admin-only, guarded server-side" treatment as `is_frozen` -
-- see enforce_profile_role_change() below.

alter table public.profiles
  add column if not exists daily_fee_tier_override_id uuid references public.driver_daily_fee_tiers (id) on delete set null;

comment on column public.profiles.daily_fee_tier_override_id is 'Super-admin-only (see enforce_profile_role_change()) - pins this driver to one specific driver_daily_fee_tiers row regardless of their completed-today count. Null = normal automatic tier-by-delivery-count behavior. Clears itself if the referenced tier is ever deleted.';

-- Extend the existing role-change guard once more: the tier override is
-- just as protected as role/is_frozen - a dispatcher updating a driver's
-- profile (e.g. saving the Team form) can't sneak a tier pin through;
-- only a super admin's update is let through.
create or replace function public.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_super_admin() then
    new.role := old.role;
  end if;
  if new.is_frozen is distinct from old.is_frozen and not public.is_super_admin() then
    new.is_frozen := old.is_frozen;
  end if;
  if new.daily_fee_tier_override_id is distinct from old.daily_fee_tier_override_id
     and not public.is_super_admin()
  then
    new.daily_fee_tier_override_id := old.daily_fee_tier_override_id;
  end if;
  return new;
end;
$$;

-- Rewritten to check the override first - same signature/meaning
-- otherwise. Now plpgsql (was a one-line sql function) since the override
-- branch needs an early return.
create or replace function public.driver_daily_fee_amount(
  p_driver_id uuid,
  p_day date default current_date
)
returns numeric
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  override_amount numeric;
begin
  select t.amount into override_amount
  from public.profiles p
  join public.driver_daily_fee_tiers t on t.id = p.daily_fee_tier_override_id
  where p.id = p_driver_id;

  if override_amount is not null then
    return override_amount;
  end if;

  return coalesce(
    (
      select t.amount
      from public.driver_daily_fee_tiers t
      where t.min_deliveries <= public.driver_completed_deliveries_on(p_driver_id, p_day)
      order by t.min_deliveries desc
      limit 1
    ),
    0
  );
end;
$$;

grant execute on function public.driver_daily_fee_amount(uuid, date) to authenticated;
