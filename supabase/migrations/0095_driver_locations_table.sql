-- SuperD: a rider's live position moves out of `profiles` into its own
-- table.
--
-- profiles is an identity table that was being used as a telemetry sink.
-- Every GPS fix rewrote the rider's profile row, and each of those writes
-- dragged the whole identity apparatus along with it:
--
--   * three BEFORE UPDATE triggers (the role guard from 0002, the
--     permission overrides from 0072, the identity and photo lock from
--     0091), each comparing a dozen fields the write never touched;
--   * assign_pending_deliveries_near_driver (0060), an AFTER UPDATE
--     trigger that ran two function calls, a settings read, a load count
--     and a proximity scan over pending deliveries - on every fix;
--   * an index update, because 0093 indexes location_updated_at, which
--     changes on every write and so defeats HOT updates;
--   * a realtime broadcast back to the rider, who is subscribed to their
--     own profile row and had just sent the position themselves.
--
-- None of that is wrong for identity. All of it is wrong four times a
-- minute per rider. A narrow table with one trigger and no identity
-- carries the same data at a fraction of the cost, and profiles goes back
-- to changing when a person changes rather than when a motorbike moves.
--
-- Nothing about behaviour changes here. The readers below are the same
-- functions, transformed mechanically: `p.last_lat` becomes `dl.lat` and
-- a join is added. Matching rules, radius, caps and the 15-minute
-- freshness window are all untouched.

create table if not exists public.driver_locations (
  driver_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);

comment on table public.driver_locations is 'A rider''s last known position. One row per rider, overwritten in place - this is a current-position table, not a track history. Written by the rider''s own app; read by the Live Map, automatic assignment, and customer tracking.';

-- Carry across whatever positions exist, so no rider goes dark at the
-- moment this migration runs.
insert into public.driver_locations (driver_id, lat, lng, updated_at)
select id, last_lat, last_lng, coalesce(location_updated_at, now())
from public.profiles
where role = 'driver' and last_lat is not null and last_lng is not null
on conflict (driver_id) do nothing;

-- Serves the freshness cut in every matching query. The old index on
-- profiles.location_updated_at (0093) is dropped below: that column is
-- going away, and the index was costing a write on every fix.
create index if not exists driver_locations_updated_idx
  on public.driver_locations (updated_at desc);

alter table public.driver_locations enable row level security;

-- A rider writes only their own position. This is the one thing about a
-- rider that they alone can say, and the one thing they must be able to
-- say freely - see 0091, where the rest of their profile is read-only to
-- them precisely so that this can stay open.
drop policy if exists "driver_locations: rider upserts own" on public.driver_locations;
create policy "driver_locations: rider upserts own"
  on public.driver_locations for insert to authenticated
  with check (driver_id = auth.uid());

drop policy if exists "driver_locations: rider updates own" on public.driver_locations;
create policy "driver_locations: rider updates own"
  on public.driver_locations for update to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

-- A rider may read their own; dispatch reads everyone's, for the Live Map
-- and for assignment.
drop policy if exists "driver_locations: rider reads own, staff read all" on public.driver_locations;
create policy "driver_locations: rider reads own, staff read all"
  on public.driver_locations for select to authenticated
  using (driver_id = auth.uid() or public.is_dispatcher_or_above());

-- ---------------------------------------------------------------------
-- The readers, pointed at the new table.
--
-- Each is the current definition, transformed mechanically rather than
-- rewritten: a join to driver_locations, and p.last_lat/last_lng/
-- location_updated_at become dl.lat/lng/updated_at. Nothing else in them
-- has been touched.
--
-- Note the join is inner, not left, in the two matching queries. That is
-- not a change in behaviour: those queries already required
-- `last_lat is not null`, so a rider who has never reported a position
-- was never a candidate. Now they simply have no row.
-- ---------------------------------------------------------------------

create or replace function public.submit_delivery_request(
  p_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text default null,
  road_distance_km double precision default null,
  scheduled_at timestamptz default null,
  customer_email text default null,
  p_vehicle_type_id uuid default null,
  p_client_ip text default null
)
returns table (
  tracking_code text,
  quoted_amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vendors%rowtype;
  s public.app_settings%rowtype;
  z public.zones%rowtype;
  v_base_fare numeric;
  v_price_per_km numeric;
  v_vehicle_extra_fee numeric;
  new_tracking_code text;
  straight_line_km double precision;
  distance_km double precision;
  amount numeric(10, 2);
  cos_angle double precision;
  resolved_zone_id uuid;
  target_driver_id uuid;
  target_status public.delivery_status;
  target_assigned_at timestamptz;
  is_due_soon boolean;
  assign_cap integer;
  radius_km numeric;
begin
  perform public.enforce_rate_limit(
    'phone:' || customer_phone, 'submit_delivery_request', 5, interval '10 minutes'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'submit_delivery_request', 20, interval '10 minutes'
  );

  select * into v from public.vendors where code = p_code and is_active limit 1;
  if not found then
    raise exception 'Unknown or inactive vendor code';
  end if;

  select * into s from public.app_settings limit 1;

  resolved_zone_id := v.zone_id;
  if dropoff_lat is not null and dropoff_lng is not null then
    resolved_zone_id := coalesce(
      public.detect_zone_for_point(dropoff_lat, dropoff_lng),
      v.zone_id
    );
  end if;

  if resolved_zone_id is not null then
    select * into z from public.zones where id = resolved_zone_id;
  end if;

  v_base_fare := coalesce(z.base_fare, s.base_fare, 0);
  v_price_per_km := coalesce(z.price_per_km, s.price_per_km, 0);

  select extra_fee into v_vehicle_extra_fee
  from public.vehicle_types where id = p_vehicle_type_id;
  v_vehicle_extra_fee := coalesce(v_vehicle_extra_fee, 0);

  if dropoff_lat is not null and dropoff_lng is not null
     and v.location_lat is not null and v.location_lng is not null then
    cos_angle := sin(radians(v.location_lat)) * sin(radians(dropoff_lat))
      + cos(radians(v.location_lat)) * cos(radians(dropoff_lat))
        * cos(radians(dropoff_lng) - radians(v.location_lng));
    straight_line_km := 6371 * acos(least(1.0, greatest(-1.0, cos_angle)));
  else
    straight_line_km := 0;
  end if;

  distance_km := greatest(coalesce(road_distance_km, 0), straight_line_km);

  amount := v_base_fare + v_price_per_km * distance_km + v_vehicle_extra_fee;

  is_due_soon := scheduled_at is null or scheduled_at <= now() + interval '15 minutes';
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);
  radius_km := coalesce(s.auto_assign_radius_km, 8);

  if v.location_lat is not null and v.location_lng is not null and is_due_soon then
    -- Tier 1: nearest eligible, online driver within the vendor's normal
    -- auto-assign radius - see 0044_proximity_based_auto_assignment.sql
    -- for the original (unbounded) version of this search.
    select p.id into target_driver_id
    from public.profiles p
      join public.driver_locations dl on dl.driver_id = p.id
    where p.role = 'driver'
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and dl.lat is not null
      and dl.lng is not null
      and dl.updated_at is not null
      and dl.updated_at > now() - interval '15 minutes'
      and public.driver_daily_fee_paid(p.id)
      and not public.driver_has_overdue_commission(p.id)
      and public.driver_under_in_transit_limit(p.id)
      and (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.status not in ('delivered', 'cancelled')
      ) < assign_cap
      and 6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(dl.lat))
        + cos(radians(v.location_lat)) * cos(radians(dl.lat))
          * cos(radians(dl.lng) - radians(v.location_lng))
      ))) <= radius_km
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(dl.lat))
        + cos(radians(v.location_lat)) * cos(radians(dl.lat))
          * cos(radians(dl.lng) - radians(v.location_lng))
      ))) asc,
      p.full_name
    limit 1;

    -- Tier 2: nobody eligible within radius_km - reward whichever online
    -- eligible driver anywhere has the best track record instead of
    -- leaving this pending. A driver with no ratings yet (coalesced to
    -- -1) always loses to one with at least a single rating.
    if target_driver_id is null then
      select p.id into target_driver_id
      from public.profiles p
        join public.driver_locations dl on dl.driver_id = p.id
      where p.role = 'driver'
        and p.is_active
        and not p.is_frozen
        and p.is_online
        and dl.lat is not null
        and dl.lng is not null
        and dl.updated_at is not null
        and dl.updated_at > now() - interval '15 minutes'
        and public.driver_daily_fee_paid(p.id)
        and not public.driver_has_overdue_commission(p.id)
        and public.driver_under_in_transit_limit(p.id)
        and (
          select count(*) from public.deliveries d
          where d.assigned_driver_id = p.id
            and d.status not in ('delivered', 'cancelled')
        ) < assign_cap
      order by
        coalesce(public.driver_average_rating(p.id), -1) desc,
        (
          select count(*) from public.deliveries d
          where d.assigned_driver_id = p.id and d.status = 'delivered'
        ) desc,
        6371 * acos(least(1.0, greatest(-1.0,
          sin(radians(v.location_lat)) * sin(radians(dl.lat))
          + cos(radians(v.location_lat)) * cos(radians(dl.lat))
            * cos(radians(dl.lng) - radians(v.location_lng))
        ))) asc,
        p.full_name
      limit 1;
    end if;
  end if;

  if target_driver_id is not null then
    target_status := 'assigned';
    target_assigned_at := now();
  else
    target_status := 'pending';
    target_assigned_at := null;
  end if;

  insert into public.deliveries (
    customer_name, customer_phone, customer_email,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    vendor_id, zone_id, created_by,
    assigned_driver_id, status, assigned_at,
    scheduled_at, auto_assigned, vehicle_type_id
  )
  values (
    customer_name, customer_phone, customer_email,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, resolved_zone_id, null,
    target_driver_id, target_status, target_assigned_at,
    scheduled_at, target_driver_id is not null, p_vehicle_type_id
  )
  returning deliveries.tracking_code into new_tracking_code;

  if amount > 0 then
    insert into public.payments (delivery_id, amount, currency)
    select id, amount, coalesce(s.currency, 'GHS')
    from public.deliveries
    where deliveries.tracking_code = new_tracking_code;
  end if;

  return query select new_tracking_code, amount, coalesce(s.currency, 'GHS');
end;
$$;

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
      join public.driver_locations dl on dl.driver_id = p.id
    where p.role = 'driver'
      and p.id <> auth.uid()
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and dl.lat is not null
      and dl.lng is not null
      and dl.updated_at is not null
      and dl.updated_at > now() - interval '15 minutes'
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
        sin(radians(origin_lat)) * sin(radians(dl.lat))
        + cos(radians(origin_lat)) * cos(radians(dl.lat))
          * cos(radians(dl.lng) - radians(origin_lng))
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

create or replace function public.get_delivery_by_tracking_code(p_tracking_code text)
returns table (
  id uuid,
  tracking_code text,
  status public.delivery_status,
  customer_name text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  pickup_lat double precision,
  pickup_lng double precision,
  driver_name text,
  driver_phone text,
  driver_lat double precision,
  driver_lng double precision,
  driver_location_updated_at timestamptz,
  created_at timestamptz,
  scheduled_at timestamptz,
  rating integer,
  rating_comment text,
  completion_pin text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    d.dropoff_lat, d.dropoff_lng,
    d.pickup_lat, d.pickup_lng,
    p.full_name as driver_name, p.phone as driver_phone,
    dl.lat as driver_lat, dl.lng as driver_lng,
    dl.updated_at as driver_location_updated_at,
    d.created_at, d.scheduled_at,
    r.rating, r.comment as rating_comment,
    case
      when d.status in ('picked_up', 'in_transit') then pin.pin
      else null
    end as completion_pin
  from public.deliveries d
  left join public.profiles p on p.id = d.assigned_driver_id
  left join public.driver_locations dl on dl.driver_id = p.id
  left join public.delivery_ratings r on r.delivery_id = d.id
  left join public.delivery_completion_pins pin on pin.delivery_id = d.id
  where d.tracking_code = p_tracking_code;
$$;

-- ---------------------------------------------------------------------
-- The auto-assign-on-movement trigger follows the data.
--
-- It used to hang off `profiles` and fire on every GPS fix, doing two
-- function calls, a settings read, a load count and a proximity scan each
-- time. It still fires on every fix - that is what it is for - but from a
-- table whose writes carry nothing else with them.
--
-- Its eligibility test moves from the trigger's WHEN clause into the
-- body: the new row is a position now, so role/is_active/is_frozen/
-- is_online are looked up rather than read off NEW. Same conditions.
-- ---------------------------------------------------------------------

create or replace function public.assign_pending_deliveries_near_driver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  eligible boolean;
  s public.app_settings%rowtype;
  radius_km numeric;
  assign_cap integer;
  current_load integer;
  target_delivery_id uuid;
begin
  -- Was the trigger's WHEN clause while this hung off profiles; the new
  -- row carries only a position, so the rider's standing is looked up.
  select p.role = 'driver' and p.is_active and not p.is_frozen and p.is_online
  into eligible
  from public.profiles p
  where p.id = new.driver_id;

  if not coalesce(eligible, false) then
    return new;
  end if;

  if not public.driver_daily_fee_paid(new.driver_id)
     or public.driver_has_overdue_commission(new.driver_id)
  then
    return new;
  end if;

  select * into s from public.app_settings limit 1;
  assign_cap := coalesce(s.zone_auto_assign_cap, 5);
  radius_km := coalesce(s.auto_assign_radius_km, 8);

  select count(*) into current_load
  from public.deliveries d
  where d.assigned_driver_id = new.driver_id
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
      where dr.delivery_id = d.id and dr.driver_id = new.driver_id
    )
    and 6371 * acos(least(1.0, greatest(-1.0,
      sin(radians(v.location_lat)) * sin(radians(new.lat))
      + cos(radians(v.location_lat)) * cos(radians(new.lat))
        * cos(radians(new.lng) - radians(v.location_lng))
    ))) <= radius_km
  order by
    6371 * acos(least(1.0, greatest(-1.0,
      sin(radians(v.location_lat)) * sin(radians(new.lat))
      + cos(radians(v.location_lat)) * cos(radians(new.lat))
        * cos(radians(new.lng) - radians(v.location_lng))
    ))) asc,
    d.created_at asc
  limit 1;

  if target_delivery_id is not null then
    perform set_config('superd.auto_assign_from_location', 'true', true);
    update public.deliveries
    set assigned_driver_id = new.driver_id,
        status = 'assigned',
        assigned_at = now(),
        auto_assigned = true
    where id = target_delivery_id;
  end if;

  return new;
end;
$$;

drop trigger if exists assign_pending_on_driver_location on public.profiles;
drop trigger if exists assign_pending_on_driver_location on public.driver_locations;

create trigger assign_pending_on_driver_location
  after insert or update of lat, lng on public.driver_locations
  for each row
  execute function public.assign_pending_deliveries_near_driver();

-- ---------------------------------------------------------------------
-- And the old home is dismantled.
--
-- The columns go rather than being left behind deprecated. A stale
-- duplicate of a rider's position is worse than none: a reader I have
-- missed would keep working and quietly serve a position from whenever
-- this migration ran, which is the kind of bug that surfaces as "dispatch
-- sent someone to the wrong side of town" weeks later. Dropped, any such
-- reader fails loudly the first time it runs.
-- ---------------------------------------------------------------------

drop index if exists public.profiles_assignable_driver_idx;

alter table public.profiles
  drop column if exists last_lat,
  drop column if exists last_lng,
  drop column if exists location_updated_at;

-- 0093's index without the location column that was defeating HOT
-- updates. What is left changes only when a rider goes on or off duty.
create index if not exists profiles_online_driver_idx
  on public.profiles (id)
  where role = 'driver' and is_active and not is_frozen and is_online;

analyze public.profiles;
analyze public.driver_locations;
