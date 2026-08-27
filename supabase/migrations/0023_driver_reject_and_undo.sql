-- SuperD: lets a driver reject a delivery assigned to them but not yet
-- accepted (still 'assigned' - before "Accept & begin trip"), sending it
-- back to the unassigned pool for a dispatcher to give to someone else.
--
-- "Undo an accidental status tap" (assigned <- in_transit <- picked_up <-
-- delivered) needs no schema change - a driver can already freely rewrite
-- `status` on their own assigned deliveries (see the "deliveries: admin or
-- assigned driver update" RLS policy), and `enforce_delivery_update()
-- doesn't restrict which status value they set, only which OTHER columns
-- they can touch. So the client just calls the same update_status path
-- with the previous status - see DeliveryStatus.previousForDriver.
--
-- Rejecting is different: it needs to null out assigned_driver_id, which
-- enforce_delivery_update() locks to its old value for anyone who isn't a
-- dispatcher or above (that's what stops a driver reassigning jobs). This
-- adds one narrow, server-checked exception for that specific transition.

create or replace function public.enforce_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_driver_reject boolean;
begin
  is_driver_reject := (
    old.status = 'assigned'
    and new.status = 'pending'
    and old.assigned_driver_id = auth.uid()
    and new.assigned_driver_id is null
  );

  if not public.is_dispatcher_or_above() then
    -- Drivers may only touch status, notes and proof of delivery on jobs
    -- assigned to them; every other column snaps back to its old value.
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
    if not is_driver_reject then
      new.assigned_driver_id := old.assigned_driver_id;
      new.assigned_at := old.assigned_at;
    end if;
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

-- The only thing that produces the exact update shape enforce_delivery_update()
-- now allows through for a non-dispatcher - re-checks the same conditions
-- server-side (assigned to the caller, still 'assigned') rather than
-- trusting the client to only call this from the right screen state.
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
end;
$$;

grant execute on function public.driver_reject_delivery(uuid) to authenticated;
