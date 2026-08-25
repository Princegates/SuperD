-- SuperD: record payments against deliveries.
--
-- This only *records* payments (cash on delivery, card, mobile money,
-- bank transfer) - it does not charge anyone. Wiring an actual payment
-- gateway (Stripe/Paystack/Flutterwave/etc) to collect money online is a
-- separate follow-up; this schema has room for it (see `gateway_reference`)
-- when that's ready.
--
-- Run this after 0002_roles_step1_enum.sql and 0002_roles_step2_policies.sql.

do $$ begin
  create type public.payment_method as enum ('cash', 'card', 'mobile_money', 'bank_transfer', 'other');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.payment_status as enum ('pending', 'paid', 'failed', 'refunded');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries (id) on delete cascade,

  amount numeric(10, 2) not null check (amount >= 0),
  currency text not null default 'USD',
  method public.payment_method not null default 'cash',
  status public.payment_status not null default 'pending',

  -- Filled in once a real payment gateway is wired up; unused for now.
  gateway_reference text,

  notes text,
  recorded_by uuid references public.profiles (id),
  paid_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.payments is 'Payment recorded against a delivery - cash/card/mobile money/bank transfer, tracked manually until a gateway is wired up.';

create index if not exists payments_delivery_idx on public.payments (delivery_id);

drop trigger if exists payments_set_updated_at on public.payments;
create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function public.set_updated_at();

create or replace function public.stamp_payment_paid_at()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' and new.paid_at is null then
    new.paid_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists payments_stamp_paid_at on public.payments;
create trigger payments_stamp_paid_at
  before update on public.payments
  for each row execute function public.stamp_payment_paid_at();

alter table public.payments enable row level security;

drop policy if exists "payments: dispatcher or assigned driver read" on public.payments;
create policy "payments: dispatcher or assigned driver read"
  on public.payments for select
  using (
    public.is_dispatcher_or_above()
    or exists (
      select 1 from public.deliveries d
      where d.id = delivery_id and d.assigned_driver_id = auth.uid()
    )
  );

drop policy if exists "payments: dispatcher or assigned driver insert" on public.payments;
create policy "payments: dispatcher or assigned driver insert"
  on public.payments for insert
  with check (
    public.is_dispatcher_or_above()
    or exists (
      select 1 from public.deliveries d
      where d.id = delivery_id and d.assigned_driver_id = auth.uid()
    )
  );

drop policy if exists "payments: dispatcher or assigned driver update" on public.payments;
create policy "payments: dispatcher or assigned driver update"
  on public.payments for update
  using (
    public.is_dispatcher_or_above()
    or exists (
      select 1 from public.deliveries d
      where d.id = delivery_id and d.assigned_driver_id = auth.uid()
    )
  );

-- Only a dispatcher/super admin can delete a recorded payment.
drop policy if exists "payments: dispatcher delete" on public.payments;
create policy "payments: dispatcher delete"
  on public.payments for delete
  using (public.is_dispatcher_or_above());

alter publication supabase_realtime add table public.payments;
