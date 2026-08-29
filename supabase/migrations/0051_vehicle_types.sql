-- SuperD: lets a super admin define the vehicle types a customer can pick
-- from on the delivery request form (Console > Settings), each with its
-- own flat surcharge added on top of the normal base-fare + per-km price
-- (0047_remove_price_cap.sql's pricing - otherwise unchanged). Seeded
-- with one row, Motorcycle at 0 surcharge, marked default - so an
-- existing deployment's pricing doesn't change at all until a super
-- admin actually adds more types, and a customer who never touches the
-- picker still gets exactly today's price.

create table if not exists public.vehicle_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  extra_fee numeric(10, 2) not null default 0 check (extra_fee >= 0),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.vehicle_types is 'Vehicle types a customer can choose on the delivery request form, each with a flat surcharge added to the base-fare + per-km price. Exactly one row is is_default (see the partial unique index below) - the picker''s starting selection, motorcycle by default.';

-- At most one default, enforced by Postgres itself rather than app code -
-- see set_default_vehicle_type() below for the only safe way to change it.
create unique index if not exists vehicle_types_one_default
  on public.vehicle_types (is_default)
  where is_default;

insert into public.vehicle_types (name, extra_fee, is_default)
values ('Motorcycle', 0, true)
on conflict (name) do nothing;

alter table public.vehicle_types enable row level security;

drop policy if exists "vehicle_types: anyone reads" on public.vehicle_types;
create policy "vehicle_types: anyone reads"
  on public.vehicle_types for select
  using (true);

drop policy if exists "vehicle_types: super admin inserts" on public.vehicle_types;
create policy "vehicle_types: super admin inserts"
  on public.vehicle_types for insert
  with check (public.is_super_admin());

drop policy if exists "vehicle_types: super admin updates" on public.vehicle_types;
create policy "vehicle_types: super admin updates"
  on public.vehicle_types for update
  using (public.is_super_admin())
  with check (public.is_super_admin());

drop policy if exists "vehicle_types: super admin deletes" on public.vehicle_types;
create policy "vehicle_types: super admin deletes"
  on public.vehicle_types for delete
  using (public.is_super_admin());

alter publication supabase_realtime add table public.vehicle_types;

-- Blocks removing whichever row is currently the default - a super admin
-- must set a different one as default first (see set_default_vehicle_type()
-- below), so there's never a moment with zero default vehicle types.
create or replace function public.prevent_default_vehicle_type_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.is_default then
    raise exception 'Set a different vehicle type as default before removing this one.';
  end if;
  return old;
end;
$$;

drop trigger if exists vehicle_types_prevent_default_delete on public.vehicle_types;
create trigger vehicle_types_prevent_default_delete
  before delete on public.vehicle_types
  for each row execute function public.prevent_default_vehicle_type_delete();

-- The only safe way to move the default from one row to another -
-- atomically clears the old one first so the partial unique index above
-- is never violated mid-change (a plain client UPDATE setting is_default
-- on a second row while the first is still true would just fail on that
-- index, which is why this isn't exposed as an editable field at all).
create or replace function public.set_default_vehicle_type(p_vehicle_type_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can change the default vehicle type.';
  end if;

  update public.vehicle_types set is_default = false where is_default;
  update public.vehicle_types set is_default = true where id = p_vehicle_type_id;

  if not found then
    raise exception 'Vehicle type not found.';
  end if;
end;
$$;

grant execute on function public.set_default_vehicle_type(uuid) to authenticated;

-- Anonymous-customer read access - the delivery request form has no
-- login at all, same "narrow RPC instead of opening RLS to anon"
-- approach get_vendor_by_code() uses in 0010_vendors_zones.sql, rather
-- than granting the anon role its own table policy.
create or replace function public.get_vehicle_types()
returns setof public.vehicle_types
language sql
security definer
set search_path = public
stable
as $$
  select * from public.vehicle_types order by extra_fee asc, name asc;
$$;

grant execute on function public.get_vehicle_types() to anon, authenticated;

-- Both pricing functions gain an optional p_vehicle_type_id - adds
-- whatever that vehicle type's extra_fee is on top of the usual
-- base-fare + per-km amount. Null (nothing selected, or an id that no
-- longer exists) means 0 extra, so the price is unchanged from before
-- this migration.
drop function if exists public.get_delivery_price_estimate(
  text, double precision, double precision, double precision
);

create or replace function public.get_delivery_price_estimate(
  p_code text,
  dropoff_lat double precision default null,
  dropoff_lng double precision default null,
  road_distance_km double precision default null,
  p_vehicle_type_id uuid default null
)
returns table (
  low_amount numeric,
  high_amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v public.vendors%rowtype;
  s public.app_settings%rowtype;
  z public.zones%rowtype;
  v_base_fare numeric;
  v_price_per_km numeric;
  v_vehicle_extra_fee numeric;
  straight_line_km double precision;
  distance_km double precision;
  cos_angle double precision;
  raw_amount numeric;
  v_high numeric;
  v_low numeric;
  resolved_zone_id uuid;
begin
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

  raw_amount := v_base_fare + v_price_per_km * distance_km + v_vehicle_extra_fee;
  v_high := raw_amount;
  v_low := raw_amount * 0.85;

  return query select v_low, v_high, coalesce(s.currency, 'GHS');
end;
$$;

grant execute on function public.get_delivery_price_estimate(
  text, double precision, double precision, double precision, uuid
) to anon, authenticated;

drop function if exists public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision, timestamptz, text
);

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
  p_vehicle_type_id uuid default null
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
begin
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

  -- Whichever online, eligible driver is physically closest to the
  -- vendor's pickup point right now - see
  -- 0044_proximity_based_auto_assignment.sql. Skipped entirely (falls to
  -- 'pending') if the vendor has no coordinates to measure from, same as
  -- always for a delivery scheduled well into the future.
  if v.location_lat is not null and v.location_lng is not null and is_due_soon then
    select p.id into target_driver_id
    from public.profiles p
    where p.role = 'driver'
      and p.is_active
      and not p.is_frozen
      and p.is_online
      and p.last_lat is not null
      and p.last_lng is not null
      and p.location_updated_at is not null
      and p.location_updated_at > now() - interval '15 minutes'
      and public.driver_daily_fee_paid(p.id)
      and (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.status not in ('delivered', 'cancelled')
      ) < assign_cap
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(p.last_lat))
        + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(v.location_lng))
      ))) asc,
      p.full_name
    limit 1;
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
    scheduled_at, auto_assigned
  )
  values (
    customer_name, customer_phone, customer_email,
    v.vendor_name, v.location_lat, v.location_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    package_description,
    v.id, resolved_zone_id, null,
    target_driver_id, target_status, target_assigned_at,
    scheduled_at, target_driver_id is not null
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

grant execute on function public.submit_delivery_request(
  text, text, text, text, double precision, double precision, text, double precision, timestamptz, text, uuid
) to anon, authenticated;
