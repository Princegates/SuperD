-- SuperD: driver commission - a flat fee owed to the business per
-- completed delivery, tracked as its own ledger (separate from
-- `payments`, which records what a customer owes for the delivery
-- itself). A super admin sets the flat fee from Console > Settings; a
-- "due" record is created automatically the moment a delivery is marked
-- delivered, and a dispatcher/super admin marks it paid once the driver
-- actually settles it (e.g. in person, weekly) - the same "record it,
-- don't try to collect it in-app" approach as customer payments.

alter table public.app_settings
  add column if not exists commission_flat_fee numeric(10, 2) not null default 0;

comment on column public.app_settings.commission_flat_fee is 'Flat amount a driver owes the business per completed delivery. 0 = commission tracking is effectively off (no due records are created).';

create table if not exists public.commission_payments (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles (id) on delete cascade,
  delivery_id uuid references public.deliveries (id) on delete set null,
  amount numeric(10, 2) not null,
  currency text not null default 'GHS',
  status text not null default 'due' check (status in ('due', 'paid', 'waived')),
  marked_paid_by uuid references public.profiles (id),
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.commission_payments is 'One row per completed delivery''s commission - created automatically (see log_commission_due() below), marked paid/waived by a dispatcher or super admin from Console > Commission.';

create index if not exists commission_payments_driver_idx on public.commission_payments (driver_id);
create index if not exists commission_payments_status_idx on public.commission_payments (status);

alter table public.commission_payments enable row level security;

drop policy if exists "commission_payments: dispatcher reads" on public.commission_payments;
create policy "commission_payments: dispatcher reads"
  on public.commission_payments for select
  using (public.is_dispatcher_or_above());

-- No insert policy at all for anon/authenticated - rows are only ever
-- created by log_commission_due() below (SECURITY DEFINER, bypasses RLS).
drop policy if exists "commission_payments: dispatcher updates" on public.commission_payments;
create policy "commission_payments: dispatcher updates"
  on public.commission_payments for update
  using (public.is_dispatcher_or_above())
  with check (public.is_dispatcher_or_above());

-- Creates a "due" commission record the moment a delivery is marked
-- delivered (and has a driver assigned) - using whatever the flat fee is
-- set to right now, so changing the fee later never rewrites history for
-- deliveries already completed.
create or replace function public.log_commission_due()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.app_settings%rowtype;
begin
  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and new.assigned_driver_id is not null
  then
    select * into s from public.app_settings limit 1;
    if coalesce(s.commission_flat_fee, 0) > 0 then
      insert into public.commission_payments (
        driver_id, delivery_id, amount, currency
      )
      values (
        new.assigned_driver_id, new.id, s.commission_flat_fee,
        coalesce(s.currency, 'GHS')
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_log_commission_due on public.deliveries;
create trigger deliveries_log_commission_due
  after update on public.deliveries
  for each row execute function public.log_commission_due();
