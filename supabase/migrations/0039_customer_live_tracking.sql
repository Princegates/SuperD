-- SuperD: a customer tracking their own order (`/t/:trackingCode`) gets
-- the same live map a vendor already sees on their orders page - the
-- assigned driver's last known position plus the drop-off point.
-- get_delivery_by_tracking_code() previously only returned the driver's
-- name/phone; this adds the same location columns get_vendor_deliveries()
-- already has. VendorDelivery (the Dart model shared by both) already
-- reads these fields - they were simply absent from this function's
-- result before now. Return shape changes, drop first.

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
  driver_name text,
  driver_phone text,
  driver_lat double precision,
  driver_lng double precision,
  driver_location_updated_at timestamptz,
  created_at timestamptz,
  scheduled_at timestamptz,
  rating integer,
  rating_comment text
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
    p.last_lat as driver_lat, p.last_lng as driver_lng,
    p.location_updated_at as driver_location_updated_at,
    d.created_at, d.scheduled_at,
    r.rating, r.comment as rating_comment
  from public.deliveries d
  left join public.profiles p on p.id = d.assigned_driver_id
  left join public.delivery_ratings r on r.delivery_id = d.id
  where d.tracking_code = p_tracking_code;
$$;

grant execute on function public.get_delivery_by_tracking_code(text) to anon, authenticated;
