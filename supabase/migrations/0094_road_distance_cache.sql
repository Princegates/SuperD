-- SuperD: cache for Google Directions results, so the same road is not
-- bought twice.
--
-- get-road-distance is called on every price quote and every ETA refresh,
-- and each call is billed. Deliveries in a city repeat the same corridors
-- constantly - the same vendor to the same few neighbourhoods, all day -
-- so most of those calls are re-asking Google a question it has already
-- answered.
--
-- Coordinates are rounded to three decimal places, roughly 110m at
-- Ghana's latitude. That is deliberately coarser than the input: two
-- pickups from opposite ends of the same shop forecourt should share a
-- cached route, and at this distance the error is far below the noise in
-- a courier price. numeric(9,3) rather than float, so the primary key
-- compares exactly - rounding two floats to 3dp does not reliably produce
-- the same bits.
--
-- No traffic dependency: get-road-distance sends no departure_time, so
-- Google returns the free-flow estimate, which is a property of the road
-- rather than of the moment. That is what makes this cacheable at all.
-- The 30-day sweep exists for roads that genuinely change - a new link, a
-- lasting closure - not for traffic.

create table if not exists public.road_distance_cache (
  origin_lat numeric(9, 3) not null,
  origin_lng numeric(9, 3) not null,
  dest_lat numeric(9, 3) not null,
  dest_lng numeric(9, 3) not null,
  distance_km double precision not null,
  duration_minutes integer,
  hits integer not null default 1,
  created_at timestamptz not null default now(),
  refreshed_at timestamptz not null default now(),
  primary key (origin_lat, origin_lng, dest_lat, dest_lng)
);

comment on table public.road_distance_cache is 'Cached Google Directions results keyed by coordinates rounded to ~110m. Written and read only by the get-road-distance Edge Function via the service role; RLS is on with no policies, so no client can reach it.';
comment on column public.road_distance_cache.hits is 'How many times this route has been served from cache rather than bought from Google. Useful for judging whether the cache is earning its keep.';

-- Lets the 30-day sweep find stale rows without scanning the table.
create index if not exists road_distance_cache_refreshed_idx
  on public.road_distance_cache (refreshed_at);

-- On with no policies at all: the service role bypasses RLS, everyone
-- else - including a signed-in dispatcher and the anon key the public
-- request form uses - gets nothing. There is no reason for a client to
-- read this, and it would otherwise leak every vendor's coordinates.
alter table public.road_distance_cache enable row level security;

-- Deletes routes untouched for 30 days. Not scheduled here - call it from
-- pg_cron if that is available, or leave it be: the table is tiny and a
-- stale row costs nothing but a slightly out-of-date distance.
create or replace function public.sweep_road_distance_cache()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.road_distance_cache
  where refreshed_at < now() - interval '30 days';
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.sweep_road_distance_cache() from public, anon, authenticated;

comment on function public.sweep_road_distance_cache() is 'Removes cached routes untouched for 30 days. Service role only.';
