-- SuperD: logs every SMS send attempt (notify-driver-assigned), so a
-- super admin can see usage per vendor for manual billing - unlike the
-- free email notifications, SMS costs real money via Twilio, so this is
-- the first piece of the "charge for what actually costs money" idea:
-- track usage now, invoice manually; automated billing is a separate,
-- bigger follow-up if it's ever needed.

create table if not exists public.sms_log (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid references public.deliveries (id) on delete set null,
  vendor_id uuid references public.vendors (id) on delete set null,
  phone text not null,
  success boolean not null,
  created_at timestamptz not null default now()
);

comment on table public.sms_log is 'One row per SMS send attempt from notify-driver-assigned. Written only by that function via the service-role key - no insert policy for anon/authenticated at all.';

create index if not exists sms_log_vendor_idx on public.sms_log (vendor_id);

alter table public.sms_log enable row level security;

drop policy if exists "sms_log: dispatcher reads" on public.sms_log;
create policy "sms_log: dispatcher reads"
  on public.sms_log for select
  using (public.is_dispatcher_or_above());

-- Per-vendor usage, this calendar month and all-time - powers the
-- Console's Finance tab. Not SECURITY DEFINER on purpose: it should run
-- with the caller's own RLS-checked privileges, same as querying the
-- tables directly would, not bypass them.
create or replace function public.get_sms_usage_by_vendor()
returns table (
  vendor_id uuid,
  vendor_name text,
  total_count bigint,
  month_count bigint
)
language sql
stable
as $$
  select
    v.id as vendor_id,
    v.vendor_name,
    count(s.id) as total_count,
    count(s.id) filter (
      where date_trunc('month', s.created_at) = date_trunc('month', now())
    ) as month_count
  from public.vendors v
  join public.sms_log s on s.vendor_id = v.id and s.success
  group by v.id, v.vendor_name
  order by month_count desc, total_count desc;
$$;

grant execute on function public.get_sms_usage_by_vendor() to authenticated;
