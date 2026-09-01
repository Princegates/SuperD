-- Fixes a driver who rejected a delivery being able to have it
-- auto-assigned right back to them - driver_reject_delivery() only ever
-- nulled out assigned_driver_id and put the delivery back to 'pending',
-- with no record of who rejected it, so neither automatic-assignment
-- path (assign_pending_deliveries_near_driver(), triggered when a driver
-- comes online/moves; driver_cancel_delivery()'s mid-trip fallback
-- search) had any way to know to skip them - if that same driver was
-- still the nearest eligible one, they'd get handed the exact delivery
-- they just turned down.
--
-- New delivery_rejections table records each (delivery, driver) pair the
-- moment a driver rejects - both automatic-assignment paths now exclude
-- any driver who's on this list for that delivery. This is deliberately
-- scoped to *automatic* assignment only: a dispatcher/super admin
-- manually assigning a delivery from the Console can still pick a driver
-- who rejected it before, since that's a deliberate human call, not the
-- accidental re-offer this fixes.

create table if not exists public.delivery_rejections (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  rejected_at timestamptz not null default now(),
  unique (delivery_id, driver_id)
);

comment on table public.delivery_rejections is 'One row per driver who has rejected a given delivery (see driver_reject_delivery()) - both automatic-assignment paths (assign_pending_deliveries_near_driver(), driver_cancel_delivery()''s fallback) exclude these pairs so a driver never gets auto-reassigned a delivery they already turned down. No RLS policies for anon/authenticated on purpose: only SECURITY DEFINER functions touch this table - a manual dispatcher assignment is unaffected either way.';

create index if not exists delivery_rejections_delivery_idx
  on public.delivery_rejections (delivery_id);

alter table public.delivery_rejections enable row level security;

-- Same body as before, plus recording who rejected it.
create or replace function public.driver_reject_delivery(p_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.deliveries
  set status = 'pending',
      assigned_driver_id = null
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status = 'assigned';

  if not found then
    raise exception 'This delivery can no longer be rejected - it may already have been picked up or reassigned.';
  end if;

  insert into public.delivery_rejections (delivery_id, driver_id)
  values (p_delivery_id, auth.uid())
  on conflict (delivery_id, driver_id) do nothing;
end;
$$;

grant execute on function public.driver_reject_delivery(uuid) to authenticated;

-- Same body as 0067_daily_commission_settlement.sql's version, plus
-- excluding a delivery this driver has already rejected from the
-- candidate search.
create or replace function public.assign_pending_deliveries_near_driver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.app_settings%rowtype;
  radius_km numeric;
  assign_cap integer;
  current_load integer;
  target_delivery_id uuid;
begin
  if not public.driver_daily_fee_paid(new.id)
     or public.driver_has_overdue_commission(new.id)
  then
    return new;
  end if;

  select * into s from public.app_settings limit 1;
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);
  radius_km := coalesce(s.auto_assign_radius_km, 8);

  select count(*) into current_load
  from public.deliveries d
  where d.assigned_driver_id = new.id
    and d.status not in ('delivered', 'cancelled');

  if current_load >= assign_cap then
    return new;
  end if;

  select d.id into target_delivery_id
  from public.deliveries d
  join public.vendors v on v.id = d.vendor_id
  where d.status = 'pending'
    and d.assigned_driver_id is null
    and v.location_lat is not null and v.location_lng is not null
    and (d.scheduled_at is null or d.scheduled_at <= now() + interval '15 minutes')
    and not exists (
      select 1 from public.delivery_rejections dr
      where dr.delivery_id = d.id and dr.driver_id = new.id
    )
    and 6371 * acos(least(1.0, greatest(-1.0,
      sin(radians(v.location_lat)) * sin(radians(new.last_lat))
      + cos(radians(v.location_lat)) * cos(radians(new.last_lat))
        * cos(radians(new.last_lng) - radians(v.location_lng))
    ))) <= radius_km
  order by
    6371 * acos(least(1.0, greatest(-1.0,
      sin(radians(v.location_lat)) * sin(radians(new.last_lat))
      + cos(radians(v.location_lat)) * cos(radians(new.last_lat))
        * cos(radians(new.last_lng) - radians(v.location_lng))
    ))) asc,
    d.created_at asc
  limit 1;

  if target_delivery_id is not null then
    perform set_config('superd.auto_assign_from_location', 'true', true);
    update public.deliveries
    set assigned_driver_id = new.id,
        status = 'assigned',
        assigned_at = now(),
        auto_assigned = true
    where id = target_delivery_id;
  end if;

  return new;
end;
$$;

-- Same body as 0067_daily_commission_settlement.sql's version, plus
-- excluding a candidate driver who's already rejected this exact
-- delivery from the mid-trip-cancellation fallback search.
create or replace function public.driver_cancel_delivery(
  p_delivery_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.deliveries%rowtype;
  s public.app_settings%rowtype;
  old_driver_name text;
  new_driver_name text;
  target_driver_id uuid;
  target_status public.delivery_status;
  assign_cap integer;
  reason_suffix text;
  note_text text;
  origin_lat double precision;
  origin_lng double precision;
begin
  select * into d from public.deliveries
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status in ('picked_up', 'in_transit')
  for update;

  if not found then
    raise exception 'This delivery can no longer be cancelled - it may already have been delivered or reassigned.';
  end if;

  select full_name, last_lat, last_lng
    into old_driver_name, origin_lat, origin_lng
  from public.profiles where id = auth.uid();

  select * into s from public.app_settings limit 1;
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);

  reason_suffix := case
    when p_reason is not null and length(trim(p_reason)) > 0
      then ' (' || trim(p_reason) || ')'
    else ''
  end;

  if origin_lat is not null and origin_lng is not null then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.id <> auth.uid()
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.last_lat is not null
      and p.last_lng is not null
      and p.location_updated_at is not null
      and p.location_updated_at > now() - interval '15 minutes'
      and public.driver_daily_fee_paid(p.id)
      and not public.driver_has_overdue_commission(p.id)
      and public.driver_under_in_transit_limit(p.id)
      and not exists (
        select 1 from public.delivery_rejections dr
        where dr.delivery_id = d.id and dr.driver_id = p.id
      )
      and (
        select count(*) from public.deliveries dd
        where dd.assigned_driver_id = p.id
          and dd.status not in ('delivered', 'cancelled')
      ) < assign_cap
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(origin_lat)) * sin(radians(p.last_lat))
        + cos(radians(origin_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(origin_lng))
      ))) asc,
      p.full_name
    limit 1;
  end if;

  if target_driver_id is not null then
    select full_name into new_driver_name from public.profiles where id = target_driver_id;
    target_status := 'assigned';
    note_text := format(
      'Cancelled by %s mid-trip%s - reassigned to %s.',
      coalesce(old_driver_name, 'the driver'), reason_suffix,
      coalesce(new_driver_name, 'another driver')
    );
  else
    target_status := 'pending';
    note_text := format(
      'Cancelled by %s mid-trip%s - no other driver available, needs manual reassignment.',
      coalesce(old_driver_name, 'the driver'), reason_suffix
    );
  end if;

  perform set_config('superd.status_note', note_text, true);

  update public.deliveries
  set status = target_status,
      assigned_driver_id = target_driver_id,
      assigned_at = null,
      picked_up_at = null,
      auto_assigned = (target_driver_id is not null)
  where id = p_delivery_id;
end;
$$;
