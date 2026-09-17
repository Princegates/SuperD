-- SuperD: lets a vendor ask for a hand-priced special delivery on behalf
-- of a customer, from their own private orders page - a self-service
-- version of what already happens when a vendor phones dispatch instead
-- (see CreateDeliveryScreen's "Pickup from a vendor" option, added for
-- exactly that call).
--
-- Deliberately its own small table rather than inserting straight into
-- `deliveries`: a special delivery's fee is set by a dispatcher, never by
-- whoever asked for it - the same rule CreateDeliveryScreen enforces for
-- a phoned-in request (its fee field is required, typed by the
-- dispatcher, never the caller). Letting a vendor's own submission create
-- a live `deliveries` row directly would mean either a fee of 0 sitting
-- in the pending/assignable queue, or a new "set a price after the fact"
-- capability - neither PaymentCard nor anything else here has one. A
-- request queue a dispatcher explicitly turns into a priced delivery (or
-- dismisses) avoids both, and costs nothing extra on the pricing side.
create table public.special_delivery_requests (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  customer_name text not null,
  customer_phone text not null,
  dropoff_address text not null,
  dropoff_lat double precision,
  dropoff_lng double precision,
  package_description text,
  notes text,
  status text not null default 'pending'
    check (status in ('pending', 'fulfilled', 'dismissed')),
  fulfilled_delivery_id uuid references public.deliveries(id),
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.special_delivery_requests is 'A vendor''s ask for a hand-priced special delivery on behalf of a customer, submitted from their private orders page - not a delivery yet. A dispatcher/super admin reviews it in Console (the Deliveries section) and either fulfills it, which creates the priced deliveries row via CreateDeliveryScreen''s vendor-pickup option, or dismisses it.';

alter table public.special_delivery_requests enable row level security;

create policy "special_delivery_requests: staff select"
  on public.special_delivery_requests for select
  using (public.is_dispatcher_or_above());

-- Same permission submit_delivery_request/manual creation both key off -
-- resolving one of these (fulfilling or dismissing) is routine dispatch
-- work, not a super-admin-only decision.
create policy "special_delivery_requests: permitted staff update"
  on public.special_delivery_requests for update
  using (public.has_permission(auth.uid(), 'create_deliveries'))
  with check (public.has_permission(auth.uid(), 'create_deliveries'));

-- No insert/delete policy for anon/authenticated - the only way in is
-- submit_special_delivery_request() below (security definer), and nothing
-- ever deletes a row; a resolved one just moves to 'fulfilled'/'dismissed'.

create index special_delivery_requests_pending_idx
  on public.special_delivery_requests (created_at desc)
  where status = 'pending';

alter publication supabase_realtime add table public.special_delivery_requests;

-- The vendor-facing submit path. Keyed by the vendor's private orders_code,
-- not the public code a customer holds - the same trust boundary
-- get_vendor_deliveries() already relies on for reads (0027/0097): the
-- orders_code is a random secret only the vendor has, so this doesn't need
-- the Turnstile/Edge Function gate the *public* code's write paths need
-- (0059_public_form_captcha_gate.sql) - that gate exists because a public
-- link is exposed to anyone, not because writing itself is risky. Still
-- rate-limited the same way as every other public write, in case a code
-- ever does leak. An inactive vendor can't submit a new one (unlike
-- reading their own history, which stays available either way).
create or replace function public.submit_special_delivery_request(
  p_orders_code text,
  customer_name text,
  customer_phone text,
  dropoff_address text,
  dropoff_lat double precision default null,
  dropoff_lng double precision default null,
  package_description text default null,
  notes text default null,
  p_client_ip text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vendor_id uuid;
  new_id uuid;
begin
  perform public.enforce_rate_limit(
    'phone:' || customer_phone, 'submit_special_delivery_request', 5, interval '10 minutes'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'submit_special_delivery_request', 20, interval '10 minutes'
  );

  select id into v_vendor_id from public.vendors
  where orders_code = p_orders_code and is_active
  limit 1;

  if v_vendor_id is null then
    raise exception 'Unknown or inactive vendor code';
  end if;

  insert into public.special_delivery_requests (
    vendor_id, customer_name, customer_phone, dropoff_address,
    dropoff_lat, dropoff_lng, package_description, notes
  )
  values (
    v_vendor_id, customer_name, customer_phone, dropoff_address,
    dropoff_lat, dropoff_lng, package_description, notes
  )
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.submit_special_delivery_request(
  text, text, text, text, double precision, double precision, text, text, text
) from public;
grant execute on function public.submit_special_delivery_request(
  text, text, text, text, double precision, double precision, text, text, text
) to anon, authenticated;
