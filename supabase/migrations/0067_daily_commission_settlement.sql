-- SuperD: per-delivery commission (commission_flat_fee/commission_percentage,
-- see 0029_commission_payments.sql/0066_commission_percentage.sql) has never
-- been a hard block on its own - 0050_bundle_commission_with_daily_fee.sql's
-- own comment says so explicitly: "Unpaid per-delivery commission still
-- isn't a hard block on its own; it just now rides along with whatever
-- daily-fee payment the driver already needs to make." A driver could
-- accumulate due commission indefinitely as long as they kept paying
-- today's daily fee.
--
-- This closes that gap: commission left `due` from a *previous* calendar
-- day (today's is still fair game - a driver has until the day ends to
-- settle it, same grace every other "daily" thing in this app gets) now
-- blocks a driver from new deliveries, the same hard way an unpaid
-- daily-fee tier already does - a real `raise exception`, not just a
-- warning, wired into every path that assigns a driver (manual, the two
-- automatic-assignment tiers, a mid-trip hand-off, and the
-- drive-into-range trigger), plus the dispatcher's own picker so they see
-- it before hitting the error. Settling it works exactly like it already
-- does today: a driver's own in-app daily-fee payment clears every `due`
-- row (see `driver_total_amount_due()`/`set_daily_fee_status()` in
-- 0050_bundle_commission_with_daily_fee.sql - unchanged, already sweeps
-- everything `due` regardless of age), or a dispatcher/super admin marks a
-- row paid/waived by hand from Console > Commission.

-- Whether [p_driver_id] has any commission still `due` from before today -
-- 0 (false) while the master commission switch is off, matching every
-- other commission/daily-fee gate in this app.
create or replace function public.driver_has_overdue_commission(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  enabled boolean;
begin
  select driver_commission_enabled into enabled from public.app_settings limit 1;
  if not coalesce(enabled, true) then
    return false;
  end if;

  return exists (
    select 1 from public.commission_payments
    where driver_id = p_driver_id
      and status = 'due'
      and created_at::date < current_date
  );
end;
$$;

grant execute on function public.driver_has_overdue_commission(uuid) to authenticated;

-- Dispatcher's manual-assignment picker (Console/New delivery) - now also
-- excludes a driver with overdue commission, same as it already does for
-- one who owes today's daily fee, so a dispatcher never picks someone the
-- database would reject anyway. Same signature/name as
-- 0031_driver_daily_fee.sql's original.
create or replace function public.unpaid_driver_ids_today()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select p.id
  from public.profiles p
  where p.role = 'driver'
    and (
      not public.driver_daily_fee_paid(p.id)
      or public.driver_has_overdue_commission(p.id)
    );
$$;

-- Same body as 0048_manual_assignment_cap.sql's version, plus the new
-- overdue-commission check alongside the existing daily-fee one.
create or replace function public.enforce_delivery_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  active_count integer;
  driver_name text;
begin
  if new.assigned_driver_id is not null then
    select coalesce(zone_auto_assign_cap, 5) into cap
    from public.app_settings limit 1;

    select count(*) into active_count
    from public.deliveries d
    where d.assigned_driver_id = new.assigned_driver_id
      and d.status not in ('delivered', 'cancelled');

    if active_count >= cap then
      select full_name into driver_name
      from public.profiles where id = new.assigned_driver_id;

      raise exception
        '% already has % active deliveries, at the cap of %. Raise the '
        'cap in Console > Settings or assign someone else.',
        coalesce(driver_name, 'This driver'), active_count, cap;
    end if;
  end if;

  if new.assigned_driver_id is not null
     and exists (
       select 1 from public.profiles p
       where p.id = new.assigned_driver_id and p.is_frozen
     )
  then
    raise exception 'That driver is currently frozen and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and not public.claim_free_day_credit(new.assigned_driver_id)
  then
    raise exception 'That driver has not paid today''s commission yet and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and public.driver_has_overdue_commission(new.assigned_driver_id)
  then
    raise exception 'That driver has unsettled commission from a previous day and cannot be assigned new deliveries until it''s paid or waived.';
  end if;

  return new;
end;
$$;

-- Same body as 0063_no_undo_after_delivered.sql's version, plus the new
-- overdue-commission check alongside the existing daily-fee one.
create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
  is_driver_cancel boolean;
  is_auto_assign_from_location boolean;
  cap integer;
  active_count integer;
  driver_name text;
begin
  is_driver_reject := (
    old.status = 'assigned'
    and new.status = 'pending'
    and old.assigned_driver_id = auth.uid()
    and new.assigned_driver_id is null
  );

  is_driver_cancel := (
    old.status in ('picked_up', 'in_transit')
    and old.assigned_driver_id = auth.uid()
    and new.status in ('assigned', 'pending')
    and new.assigned_driver_id is distinct from old.assigned_driver_id
  );

  is_auto_assign_from_location := coalesce(
    current_setting('superd.auto_assign_from_location', true), ''
  ) = 'true';

  if not public.is_dispatcher_or_above() then
    new.tracking_code := old.tracking_code;
    new.customer_name := old.customer_name;
    new.customer_phone := old.customer_phone;
    new.pickup_address := old.pickup_address;
    new.pickup_lat := old.pickup_lat;
    new.pickup_lng := old.pickup_lng;
    new.dropoff_address := old.dropoff_address;
    new.dropoff_lat := old.dropoff_lat;
    new.dropoff_lng := old.dropoff_lng;
    new.package_description := old.package_description;
    new.created_by := old.created_by;
    if not (is_driver_reject or is_driver_cancel or is_auto_assign_from_location) then
      new.assigned_driver_id := old.assigned_driver_id;
      new.assigned_at := old.assigned_at;
    end if;

    if old.status = 'assigned'
       and new.status is distinct from 'assigned'
       and not is_driver_reject
       and exists (
         select 1 from public.profiles p
         where p.id = auth.uid() and p.is_frozen
       )
    then
      raise exception 'Your account is currently frozen - contact dispatch before accepting new deliveries.';
    end if;

    if new.status = 'delivered'
       and old.status is distinct from 'delivered'
       and coalesce(current_setting('superd.pin_verified', true), '') is distinct from 'true'
    then
      raise exception 'Enter the delivery PIN the customer gives you to mark this delivered.';
    end if;

    if old.status = 'delivered' and new.status is distinct from 'delivered' then
      raise exception 'This delivery is already marked delivered and cannot be undone - the customer already confirmed receipt with the PIN.';
    end if;
  end if;

  if new.assigned_driver_id is null then
    new.auto_assigned := false;
  elsif new.assigned_driver_id is distinct from old.assigned_driver_id
        and not is_driver_cancel
        and public.is_dispatcher_or_above()
  then
    new.auto_assigned := false;
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
  then
    select coalesce(zone_auto_assign_cap, 5) into cap
    from public.app_settings limit 1;

    select count(*) into active_count
    from public.deliveries d
    where d.assigned_driver_id = new.assigned_driver_id
      and d.status not in ('delivered', 'cancelled')
      and d.id <> old.id;

    if active_count >= cap then
      select full_name into driver_name
      from public.profiles where id = new.assigned_driver_id;

      raise exception
        '% already has % active deliveries, at the cap of %. Raise the '
        'cap in Console > Settings or assign someone else.',
        coalesce(driver_name, 'This driver'), active_count, cap;
    end if;
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and exists (
       select 1 from public.profiles p
       where p.id = new.assigned_driver_id and p.is_frozen
     )
  then
    raise exception 'That driver is currently frozen and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and not public.claim_free_day_credit(new.assigned_driver_id)
  then
    raise exception 'That driver has not paid today''s commission yet and cannot be assigned new deliveries.';
  end if;

  if new.assigned_driver_id is not null
     and new.assigned_driver_id is distinct from old.assigned_driver_id
     and public.driver_has_overdue_commission(new.assigned_driver_id)
  then
    raise exception 'That driver has unsettled commission from a previous day and cannot be assigned new deliveries until it''s paid or waived.';
  end if;

  if new.status = 'assigned' and old.status is distinct from 'assigned' and new.assigned_at is null then
    new.assigned_at := now();
  end if;
  if new.status = 'picked_up' and old.status is distinct from 'picked_up' then
    new.picked_up_at := now();
  end if;
  if new.status = 'delivered' and old.status is distinct from 'delivered' then
    new.delivered_at := now();
  end if;

  return new;
end;
$$;

-- Same body as 0061_fix_location_auto_assign_permission.sql's version,
-- plus the new overdue-commission check alongside the existing early
-- daily-fee bail-out.
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

-- Same body as 0062_in_transit_assignment_limit.sql's version, plus the
-- new overdue-commission check on the mid-trip hand-off candidate search
-- alongside the existing daily-fee one.
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

-- Same body/signature as 0065_delivery_vehicle_type.sql's version, plus
-- the new overdue-commission check on both auto-assign tiers' candidate
-- searches alongside the existing daily-fee one.
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
  radius_km numeric;
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
  radius_km := coalesce(s.auto_assign_radius_km, 8);

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
      and not public.driver_has_overdue_commission(p.id)
      and (
        select count(*) from public.deliveries d
        where d.assigned_driver_id = p.id
          and d.status not in ('delivered', 'cancelled')
      ) < assign_cap
      and 6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(p.last_lat))
        + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(v.location_lng))
      ))) <= radius_km
    order by
      6371 * acos(least(1.0, greatest(-1.0,
        sin(radians(v.location_lat)) * sin(radians(p.last_lat))
        + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
          * cos(radians(p.last_lng) - radians(v.location_lng))
      ))) asc,
      p.full_name
    limit 1;

    if target_driver_id is null then
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
        and not public.driver_has_overdue_commission(p.id)
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
          sin(radians(v.location_lat)) * sin(radians(p.last_lat))
          + cos(radians(v.location_lat)) * cos(radians(p.last_lat))
            * cos(radians(p.last_lng) - radians(v.location_lng))
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
