-- SuperD: shows the delivery-completion PIN (0056_delivery_completion_pin.sql)
-- on the customer's own public tracking page (/t/:trackingCode), not just
-- in the SMS/email sent when the driver picks the package up - a customer
-- who deleted that text or can't find the email shouldn't be stuck unable
-- to complete their own delivery.
--
-- Only get_delivery_by_tracking_code() changes - this is still the one
-- table (delivery_completion_pins) with no anon/authenticated RLS
-- policies at all, so a driver's own client (which freely reads
-- everything else off deliveries) still never sees it, and neither does
-- a vendor via get_vendor_deliveries(), which this migration doesn't
-- touch. Revealed only while the PIN is actually useful - status
-- 'picked_up' or 'in_transit', the same window the SMS/email already
-- targets - not before (nothing to give the driver yet) and not once
-- 'delivered' (already used).

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
