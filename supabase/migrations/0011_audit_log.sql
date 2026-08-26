-- SuperD: audit log for the super-admin Console.
--
-- Records who did what, for accountability across role changes, staff
-- and vendor management, driver assignment, and payments. There's
-- deliberately no insert/update/delete policy for anon/authenticated on
-- this table - the only way a row gets written is through
-- `log_audit_event`, which runs as the table owner (security definer) and
-- stamps the *real* caller (`auth.uid()`) as the actor, so a client can't
-- forge an entry under someone else's name or edit history after the fact.

create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id),
  actor_name text,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  summary text not null,
  created_at timestamptz not null default now()
);

create index if not exists audit_log_created_at_idx
  on public.audit_log (created_at desc);

alter table public.audit_log enable row level security;

drop policy if exists "audit_log: super admin reads" on public.audit_log;
create policy "audit_log: super admin reads"
  on public.audit_log for select
  using (public.is_super_admin());

create or replace function public.log_audit_event(
  action text,
  entity_type text,
  entity_id uuid,
  summary text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_name text;
begin
  select full_name into caller_name from public.profiles where id = auth.uid();
  insert into public.audit_log (actor_id, actor_name, action, entity_type, entity_id, summary)
  values (auth.uid(), caller_name, action, entity_type, entity_id, summary);
end;
$$;

-- Any signed-in staff member can log an event about their own action -
-- what's actually shown is gated by the select policy above, so only a
-- super admin can ever read the log back.
grant execute on function public.log_audit_event(text, text, uuid, text)
  to authenticated;
