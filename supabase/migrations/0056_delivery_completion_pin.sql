-- SuperD: closes the "mark delivered from anywhere" fraud gap flagged in
-- the last audit - a driver could tap "Mark delivered" the instant they
-- were assigned, with no proof the customer ever actually received
-- anything, and both the commission and payment logic key off that
-- status. This adds a 4-digit PIN the customer hands the driver in
-- person: generated the moment a driver is assigned, texted/emailed to
-- the customer once the driver picks the package up (see
-- notify-delivery-events), and required to complete the delivery.
--
-- The PIN lives in its own table with RLS enabled and NO policies for
-- anon/authenticated - a default-deny table only a SECURITY DEFINER
-- function (or the service-role key) can read. Keeping it out of the
-- deliveries table entirely means a driver's own client, which freely
-- selects * off deliveries (watchById/watchDriverDeliveries), can never
-- see the value they're supposed to be collecting from the customer -
-- column-level GRANT/REVOKE on deliveries itself would either need
-- every driver-facing query rewritten to an explicit column list or
-- break outright on `select *`.

create table if not exists public.delivery_completion_pins (
  delivery_id uuid primary key references public.deliveries (id) on delete cascade,
  pin text not null,
  created_at timestamptz not null default now()
);

comment on table public.delivery_completion_pins is
  'Customer-known PIN required to mark a delivery delivered - see complete_delivery_with_pin(). No RLS policies for anon/authenticated on purpose: this table is only ever touched via SECURITY DEFINER functions or the service-role key.';

alter table public.delivery_completion_pins enable row level security;

-- Regenerates the PIN every time a delivery is newly (re)assigned a
-- driver, same "did assigned_driver_id actually change" shape as
-- isNewAssignment in notify-delivery-events. Re-picking a fresh PIN on
-- reassignment means a delivery handed to a second driver after the
-- first one cancelled doesn't leave the earlier driver's customer
-- conversation still describing a code that's about to matter again.
create or replace function public.generate_delivery_completion_pin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_driver_id is not null
     and (tg_op = 'INSERT' or old.assigned_driver_id is distinct from new.assigned_driver_id)
  then
    insert into public.delivery_completion_pins (delivery_id, pin)
    values (new.id, lpad(floor(random() * 10000)::int::text, 4, '0'))
    on conflict (delivery_id) do update
      set pin = excluded.pin, created_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_generate_completion_pin on public.deliveries;
create trigger deliveries_generate_completion_pin
after insert or update on public.deliveries
for each row execute function public.generate_delivery_completion_pin();

-- The only path allowed to set status = 'delivered' for a driver (see the
-- matching check added to enforce_delivery_update() below). Verifies the
-- PIN the driver was just given by the customer, then flips
-- superd.pin_verified for the rest of this transaction so the trigger
-- lets the status change through, and deletes the PIN - it's spent.
create or replace function public.complete_delivery_with_pin(
  p_delivery_id uuid,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expected_pin text;
begin
  select pin into v_expected_pin
  from public.delivery_completion_pins
  where delivery_id = p_delivery_id;

  if v_expected_pin is null then
    raise exception 'No delivery PIN is on file for this delivery - contact dispatch.';
  end if;

  if btrim(p_pin) is distinct from v_expected_pin then
    raise exception 'That PIN doesn''t match. Ask the customer to confirm it again.';
  end if;

  perform set_config('superd.pin_verified', 'true', true);

  update public.deliveries
  set status = 'delivered'
  where id = p_delivery_id
    and assigned_driver_id = auth.uid()
    and status = 'picked_up';

  if not found then
    raise exception 'This delivery cannot be marked delivered right now.';
  end if;

  delete from public.delivery_completion_pins where delivery_id = p_delivery_id;
end;
$$;

grant execute on function public.complete_delivery_with_pin(uuid, text) to authenticated;

-- Same signature as the version being replaced (0048_manual_assignment_cap.sql)
-- - everything is unchanged except the new PIN check, added alongside the
-- existing frozen-driver check inside the "caller isn't a dispatcher"
-- block so a dispatcher/admin correcting a status from the Console is
-- never asked for a PIN, only a driver tapping through their own app is.
create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
  is_driver_cancel boolean;
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
    if not (is_driver_reject or is_driver_cancel) then
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
