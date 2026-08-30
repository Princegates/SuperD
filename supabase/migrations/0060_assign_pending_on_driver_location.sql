-- SuperD: automatically assigns a still-unclaimed ("pending") delivery to
-- a driver the moment they come within a vendor's auto-assign radius,
-- instead of only ever trying to assign at the moment the delivery was
-- created (submit_delivery_request's own tier-1/tier-2 search, see
-- 0044_proximity_based_auto_assignment.sql and
-- 0052_high_performer_assignment_fallback.sql).
--
-- A delivery only ever stays "pending" today when neither of those tiers
-- could find an eligible driver at creation time (nobody online within
-- radius, and nobody online anywhere with room under the per-driver cap)
-- - a fairly rare gap, but a real one: a driver who was offline, over
-- cap, or simply too far away then can close it later just by driving
-- into range. A driver's location is written with a plain client-side
-- update on profiles (see ProfileRepository.updateLocation) rather than
-- through any RPC, so a trigger on profiles is the only server-side hook
-- available for this - same reasoning as 0044's use of a straight
-- haversine distance check rather than PostGIS.
--
-- Deliberately narrow in scope, matching tier-1 exactly (same radius,
-- same eligibility checks, same distance formula) rather than tier-2's
-- any-distance/best-rating fallback: this is specifically about a driver
-- entering range, not about re-running the full assignment search on
-- every location ping. Assigns at most one delivery per trigger firing
-- (the nearest eligible one) - a driver with room for more than one
-- picks up the rest on their next location update, which happens
-- frequently while driving.

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
  if not public.driver_daily_fee_paid(new.id) then
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

drop trigger if exists assign_pending_on_driver_location on public.profiles;
create trigger assign_pending_on_driver_location
  after update of last_lat, last_lng, is_online on public.profiles
  for each row
  when (
    new.role = 'driver' and new.is_active and not new.is_frozen and new.is_online
    and new.last_lat is not null and new.last_lng is not null
    and (
      new.last_lat is distinct from old.last_lat
      or new.last_lng is distinct from old.last_lng
      or new.is_online is distinct from old.is_online
    )
  )
  execute function public.assign_pending_deliveries_near_driver();
