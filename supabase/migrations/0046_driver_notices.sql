-- SuperD: lets a dispatcher/super admin post a short notice to drivers -
-- either a broadcast (every driver sees it, e.g. a promotion or a
-- platform-wide heads-up) or targeted at one specific driver (a direct
-- message). Shown as a banner on the driver's own dashboard, dismissible
-- per-driver so closing it doesn't hide it from anyone else - a broadcast
-- notice is one row, not one row per driver, so dismissing it needs to
-- record *who* dismissed it rather than just a boolean.

create table if not exists public.driver_notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  target_driver_id uuid references public.profiles (id) on delete cascade,
  created_by uuid references public.profiles (id) on delete set null,
  is_active boolean not null default true,
  expires_at timestamptz,
  dismissed_by uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

comment on table public.driver_notices is 'A notice shown on a driver''s dashboard - target_driver_id null means every driver sees it (a broadcast, e.g. a promotion), set means only that one driver (a direct message). is_active false or expires_at in the past hides it from drivers entirely, without deleting the record. dismissed_by tracks which drivers have closed a broadcast notice for themselves - see dismiss_driver_notice() below.';

create index if not exists driver_notices_target_driver_idx on public.driver_notices (target_driver_id);
create index if not exists driver_notices_active_idx on public.driver_notices (is_active);

alter table public.driver_notices enable row level security;

-- A driver sees only what's meant for them (broadcast or their own
-- targeted notice), and only while it's actually live - RLS hides an
-- inactive/expired one entirely rather than relying on the client to
-- filter it out.
drop policy if exists "driver_notices: driver reads own" on public.driver_notices;
create policy "driver_notices: driver reads own"
  on public.driver_notices for select
  using (
    (target_driver_id is null or target_driver_id = auth.uid())
    and is_active
    and (expires_at is null or expires_at > now())
  );

-- A dispatcher/super admin manages notices from Console > Notices and
-- needs to see everything, including inactive/expired/targeted-at-
-- someone-else ones, to review what's been sent.
drop policy if exists "driver_notices: dispatcher reads all" on public.driver_notices;
create policy "driver_notices: dispatcher reads all"
  on public.driver_notices for select
  using (public.is_dispatcher_or_above());

drop policy if exists "driver_notices: dispatcher inserts" on public.driver_notices;
create policy "driver_notices: dispatcher inserts"
  on public.driver_notices for insert
  with check (public.is_dispatcher_or_above());

drop policy if exists "driver_notices: dispatcher updates" on public.driver_notices;
create policy "driver_notices: dispatcher updates"
  on public.driver_notices for update
  using (public.is_dispatcher_or_above())
  with check (public.is_dispatcher_or_above());

drop policy if exists "driver_notices: dispatcher deletes" on public.driver_notices;
create policy "driver_notices: dispatcher deletes"
  on public.driver_notices for delete
  using (public.is_dispatcher_or_above());

alter publication supabase_realtime add table public.driver_notices;

-- The one way a driver ever writes to this table - appending their own id
-- to dismissed_by, and only for a notice actually meant for them. Kept as
-- a narrow SECURITY DEFINER function rather than an UPDATE policy so a
-- driver can never touch title/body/target/is_active, only ever add
-- themselves to the dismissal list.
create or replace function public.dismiss_driver_notice(p_notice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select role from public.profiles where id = auth.uid()) is distinct from 'driver' then
    raise exception 'Only a driver can dismiss their own notice.';
  end if;

  update public.driver_notices
  set dismissed_by = array_append(dismissed_by, auth.uid())
  where id = p_notice_id
    and not (auth.uid() = any(dismissed_by))
    and (target_driver_id is null or target_driver_id = auth.uid());
end;
$$;

grant execute on function public.dismiss_driver_notice(uuid) to authenticated;
