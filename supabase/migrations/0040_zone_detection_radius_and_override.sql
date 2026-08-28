-- SuperD: two follow-ups to automatic zone detection
-- (0033_zone_auto_recognition_and_cap.sql).
--
-- 1. The "how close counts as this zone" radius was hardcoded at 5km in
--    detect_zone_for_point()'s third parameter, which nothing ever
--    actually overrode - every call site used the 2-arg form. Move it
--    into app_settings instead, so a super admin can tune it from
--    Console > Settings the same way the zone auto-assign cap already
--    works, without a code change.
--
-- 2. A delivery's zone_id was only ever set once, at creation
--    (auto-detected or copied from the vendor). There was no way to
--    correct it afterward if detection got it wrong or a dispatcher
--    just disagrees - the Console's delivery detail screen now has a
--    plain "Zone" dropdown next to "Assigned driver" for this. No new
--    RLS needed: a dispatcher/super admin can already update any column
--    on a delivery they can see (see enforce_delivery_update() - it only
--    resets specific fields for a non-dispatcher caller).

alter table public.app_settings
  add column if not exists zone_detection_radius_km numeric(10, 2) not null default 5;

alter table public.app_settings
  drop constraint if exists app_settings_zone_detection_radius_km_check,
  add constraint app_settings_zone_detection_radius_km_check
    check (zone_detection_radius_km between 1 and 50);

comment on column public.app_settings.zone_detection_radius_km is 'How close (km) a delivery''s drop-off must be to a zone_location for detect_zone_for_point() to trust it. Always 1-50.';

-- Signature changes (drops the unused p_max_km param) - drop first.
drop function if exists public.detect_zone_for_point(double precision, double precision, double precision);

create or replace function public.detect_zone_for_point(
  p_lat double precision,
  p_lng double precision
)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select zone_id
  from (
    select
      zl.zone_id,
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(p_lat)) * sin(radians(zl.lat))
        + cos(radians(p_lat)) * cos(radians(zl.lat))
          * cos(radians(zl.lng) - radians(p_lng))
      ))) as distance_km
    from public.zone_locations zl
    where zl.lat is not null and zl.lng is not null
  ) nearest
  where distance_km <= (
    select coalesce(zone_detection_radius_km, 5) from public.app_settings limit 1
  )
  order by distance_km asc
  limit 1
$$;

grant execute on function public.detect_zone_for_point(double precision, double precision) to anon, authenticated;
