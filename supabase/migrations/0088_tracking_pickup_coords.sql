-- SuperD: adds the pickup point to what a customer's tracking page can
-- read, so the ETA can cover the leg before collection too.
--
-- The page shows a live "arriving in about N min" from the rider's own
-- position. That only made sense once they had the parcel, because
-- before then they are riding to the shop and a time-to-your-door would
-- be answering a different question. But "assigned" is exactly when
-- someone stares at the page, and they were being shown nothing.
--
-- With the pickup point available, the same widget answers the right
-- question at each stage: how long until the rider reaches the shop,
-- then how long until they reach you.
--
-- Nothing sensitive is added. This is the address of the shop the
-- customer themselves ordered from - already on the vendor's public
-- page, and already the visible half of the map they are looking at.
-- The function is otherwise identical to 0064's, which this replaces.

drop function if exists public.get_delivery_by_tracking_code(text);

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
    p.last_lat as driver_lat, p.last_lng as driver_lng,
    p.location_updated_at as driver_location_updated_at,
    d.created_at, d.scheduled_at,
    r.rating, r.comment as rating_comment,
    case
      when d.status in ('picked_up', 'in_transit') then pin.pin
      else null
    end as completion_pin
  from public.deliveries d
  left join public.profiles p on p.id = d.assigned_driver_id
  left join public.delivery_ratings r on r.delivery_id = d.id
  left join public.delivery_completion_pins pin on pin.delivery_id = d.id
  where d.tracking_code = p_tracking_code;
$$;

grant execute on function public.get_delivery_by_tracking_code(text) to anon, authenticated;
