-- SuperD: two readers 0095 broke, and the check that should have caught
-- them before it shipped.
--
-- 0095 moved a rider's position to driver_locations and dropped
-- profiles.last_lat/last_lng/location_updated_at. It transformed the
-- readers it had found by rewriting `p.last_lat` into `dl.lat` and adding
-- a join - which is exactly as reliable as the search that produced the
-- list, and the search was a grep for that one spelling.
--
-- Two readers were spelled differently and were missed:
--
--   get_vendor_deliveries  - never transformed at all. Its latest
--     definition was back in 0034, and the grep that built 0095's list
--     was reading the *files* that mentioned the columns rather than the
--     functions that were currently installed, so a function last touched
--     twelve migrations earlier did not stand out. Every load of a
--     vendor's orders board has been failing since 0095 was applied.
--
--   driver_cancel_delivery - transformed, but only where the columns were
--     qualified. One query inside it selects them bare
--     ("select full_name, last_lat, last_lng from public.profiles"), and
--     the regex keyed on "p." walked straight past it. A rider cancelling
--     a job mid-trip has been hitting an error since.
--
-- Both fail loudly rather than silently, which is what dropping the
-- columns rather than deprecating them bought - but loudly in production
-- is still production. The real lesson is that the list should have come
-- from pg_proc on the built schema, not from grep over the migration
-- files; the query that found these is in the README.

create or replace function public.get_vendor_deliveries(p_orders_code text)
returns table (
  id uuid,
  tracking_code text,
  status public.delivery_status,
  customer_name text,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  driver_name text,
  driver_phone text,
  driver_lat double precision,
  driver_lng double precision,
  driver_location_updated_at timestamptz,
  created_at timestamptz,
  scheduled_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
    d.dropoff_lat, d.dropoff_lng,
    p.full_name as driver_name, p.phone as driver_phone,
    dl.lat as driver_lat, dl.lng as driver_lng,
    dl.updated_at as driver_location_updated_at,
    d.created_at, d.scheduled_at
  from public.deliveries d
  join public.vendors v on v.id = d.vendor_id
  left join public.profiles p on p.id = d.assigned_driver_id
  left join public.driver_locations dl on dl.driver_id = p.id
  where v.orders_code = p_orders_code
  order by d.created_at desc;
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

  select p.full_name, dl.lat, dl.lng
    into old_driver_name, origin_lat, origin_lng
  from public.profiles p
  left join public.driver_locations dl on dl.driver_id = p.id
  where p.id = auth.uid();

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
