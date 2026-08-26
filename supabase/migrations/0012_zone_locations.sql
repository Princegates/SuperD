-- SuperD: named locations within a zone.
--
-- A zone is more than just a name - a super admin can pin the specific
-- places/landmarks that make it up (e.g. the "East Legon" zone might list
-- "American House", "Trasacco Valley", ...). Drivers and vendors still
-- just pick the zone itself from a dropdown; these locations are
-- reference data for whoever's managing the zone, not something anyone
-- else needs to choose between.

create table if not exists public.zone_locations (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones (id) on delete cascade,
  name text not null,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now()
);

create index if not exists zone_locations_zone_idx
  on public.zone_locations (zone_id);

alter table public.zone_locations enable row level security;

-- Same shape as `zones` itself: readable by anyone (a dropdown showing
-- zone coverage might want this later), mutable only by a super admin.
drop policy if exists "zone_locations: anyone reads" on public.zone_locations;
create policy "zone_locations: anyone reads"
  on public.zone_locations for select
  using (true);

drop policy if exists "zone_locations: super admin inserts" on public.zone_locations;
create policy "zone_locations: super admin inserts"
  on public.zone_locations for insert
  with check (public.is_super_admin());

drop policy if exists "zone_locations: super admin updates" on public.zone_locations;
create policy "zone_locations: super admin updates"
  on public.zone_locations for update
  using (public.is_super_admin())
  with check (public.is_super_admin());

drop policy if exists "zone_locations: super admin deletes" on public.zone_locations;
create policy "zone_locations: super admin deletes"
  on public.zone_locations for delete
  using (public.is_super_admin());
