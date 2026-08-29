-- SuperD: a customer directory for customer-service lookups - one row per
-- customer (keyed by phone, the one field every delivery request already
-- requires), with their name/email/last-known address kept current and
-- linkable to their full delivery history. Super-admin-only: unlike every
-- other Console section, this is NOT opened up to an auditor - customer
-- contact details aren't something an audit/oversight role needs to see,
-- so this table's RLS is is_super_admin() specifically, the same way
-- Settings/Zones/fee-tier writes already are.
--
-- Populated automatically, not by hand - a trigger on `deliveries` upserts
-- into this table on every insert, so it stays current no matter which
-- path creates a delivery (a customer's own request via
-- submit_delivery_request(), or a dispatcher using CreateDeliveryScreen).
-- Nothing is ever deleted from `deliveries` itself to build this - the
-- customer's info stays in the system exactly as already required,
-- this just gives it a super-admin-only front door of its own instead of
-- only ever being visible one delivery at a time.

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  full_name text not null,
  email text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.customers is 'One row per customer, keyed by phone - name/email/last-known address kept current via upsert_customer_from_delivery(). Super-admin-only (see RLS below); not exposed to a dispatcher or auditor. address is the most recent delivery''s drop-off address, not necessarily a permanent home address.';

create index if not exists customers_full_name_idx on public.customers (full_name);

alter table public.customers enable row level security;

drop policy if exists "customers: super admin reads" on public.customers;
create policy "customers: super admin reads"
  on public.customers for select
  using (public.is_super_admin());

-- Keeps a customer's record current from whichever delivery just came in -
-- runs as the table owner (security definer) since neither a customer
-- (anon, via submit_delivery_request()) nor a dispatcher has - or should
-- need - direct write access to public.customers themselves.
create or replace function public.upsert_customer_from_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.customer_phone is null or trim(new.customer_phone) = '' then
    return new;
  end if;

  insert into public.customers (phone, full_name, email, address, created_at, updated_at)
  values (
    trim(new.customer_phone),
    new.customer_name,
    new.customer_email,
    new.dropoff_address,
    now(),
    now()
  )
  on conflict (phone) do update
  set full_name = excluded.full_name,
      email = coalesce(excluded.email, public.customers.email),
      address = excluded.address,
      updated_at = now();

  return new;
end;
$$;

drop trigger if exists deliveries_upsert_customer on public.deliveries;
create trigger deliveries_upsert_customer
  after insert on public.deliveries
  for each row
  execute function public.upsert_customer_from_delivery();

-- Backfill from every delivery that already exists - one row per phone,
-- seeded from that phone's most recent delivery so the directory isn't
-- empty for anyone already using the app.
insert into public.customers (phone, full_name, email, address, created_at, updated_at)
select distinct on (trim(d.customer_phone))
  trim(d.customer_phone),
  d.customer_name,
  d.customer_email,
  d.dropoff_address,
  d.created_at,
  d.created_at
from public.deliveries d
where d.customer_phone is not null and trim(d.customer_phone) <> ''
order by trim(d.customer_phone), d.created_at desc
on conflict (phone) do nothing;
