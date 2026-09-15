-- SuperD: rate-limit the unauthenticated read endpoints - but count
-- misses, not requests.
--
-- get_delivery_by_tracking_code is granted to anon and returns a
-- customer's name, their drop-off address, the rider's name, phone and
-- live position, and - while the delivery is picked_up or in_transit -
-- the completion PIN. The only thing guarding all of that is an 8-hex
-- tracking code: 32 bits. With roughly fifteen thousand deliveries on
-- file, a blind guess lands about one in 286,000, so a few thousand
-- requests a second turns up a real customer record every few minutes.
-- The code is a bearer token, and it was an unthrottled one.
--
-- The obvious fix - a cap on requests per IP - would have been worse than
-- the problem. Both this and the vendor orders board are polled every
-- five seconds by the pages that use them (see vendor_repository.dart),
-- and Ghanaian mobile carriers NAT many subscribers behind one address:
-- a single IP can legitimately produce tens of thousands of requests an
-- hour. A cap low enough to stop an attacker would have cut off real
-- customers watching real parcels.
--
-- So only misses count. A customer polls one code that exists; a guesser
-- almost never hits one. Twenty misses an hour per IP leaves room for
-- someone mistyping a code off a receipt and stops enumeration dead,
-- while a legitimate poller never touches the limit no matter how long
-- they watch.
--
-- Fails open if the IP is unknown: 'ip:' || null is null, and
-- enforce_rate_limit returns early on a null key. An endpoint that stops
-- working because a header went missing would be a worse outcome than
-- one that stops counting.

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
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select
      d.id, d.tracking_code, d.status, d.customer_name, d.dropoff_address,
      d.dropoff_lat, d.dropoff_lng,
      d.pickup_lat, d.pickup_lng,
      p.full_name as driver_name, p.phone as driver_phone,
      dl.lat as driver_lat, dl.lng as driver_lng,
      dl.updated_at as driver_location_updated_at,
      d.created_at, d.scheduled_at,
      -- Explicit cast: delivery_ratings.rating is smallint while this
      -- function has always declared integer. A language-sql body
      -- coerced that silently; return query in plpgsql will not.
      r.rating::integer, r.comment as rating_comment,
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

  -- Only misses are counted. A real customer polls one code that
  -- exists, every five seconds, for as long as their parcel is moving -
  -- and in Ghana a whole carrier's worth of them can share one NAT
  -- address, so a limit on requests would throttle the legitimate and
  -- barely inconvenience an attacker. A guesser's lookups almost all
  -- miss, which is the signal worth counting.
  if not found then
    perform public.enforce_rate_limit(
      'ip:' || public.request_ip(), 'tracking_code_miss', 20, interval '1 hour'
    );
  end if;
end;
$$;


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
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
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

  -- "No rows" is ambiguous here in a way it is not for a tracking code:
  -- a brand-new vendor with a perfectly good orders code has no orders
  -- yet, and polls this every five seconds while waiting for their first
  -- one. Counting that as a miss would lock them out inside two minutes.
  -- So the miss is an orders code that matches no vendor at all.
  if not exists (
    select 1 from public.vendors where orders_code = p_orders_code
  ) then
    perform public.enforce_rate_limit(
      'ip:' || public.request_ip(), 'vendor_orders_miss', 20, interval '1 hour'
    );
  end if;
end;
$$;


create or replace function public.get_vendor_by_code(p_code text)
returns table (
  id uuid,
  vendor_name text,
  zone_name text,
  location_lat double precision,
  location_lng double precision,
  is_active boolean,
  subscription_fee_amount numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select
      v.id, v.vendor_name, z.name as zone_name, v.location_lat, v.location_lng,
      v.is_active, v.subscription_fee_amount,
      -- Qualified: in plpgsql the returns-table columns are variables, so
    -- a bare "currency" here resolves to the output column rather than
    -- the app_settings one. Same trap as 0075.
    coalesce((select a.currency from public.app_settings a limit 1), 'GHS')
    from public.vendors v
    left join public.zones z on z.id = v.zone_id
    where v.code = p_code;

  -- Only misses are counted. A real customer polls one code that
  -- exists, every five seconds, for as long as their parcel is moving -
  -- and in Ghana a whole carrier's worth of them can share one NAT
  -- address, so a limit on requests would throttle the legitimate and
  -- barely inconvenience an attacker. A guesser's lookups almost all
  -- miss, which is the signal worth counting.
  if not found then
    perform public.enforce_rate_limit(
      'ip:' || public.request_ip(), 'vendor_code_miss', 20, interval '1 hour'
    );
  end if;
end;
$$;
