-- SuperD: a single row of app-wide settings, starting with the currency
-- payments are recorded in. This is a self-hosted, single-tenant app, so
-- one row is enough - the `id` singleton trick (a boolean primary key that
-- can only ever be `true`) blocks a second row from ever being inserted.
--
-- Only a super admin can change it (see the Settings tab in the Console);
-- everyone signed in can read it, since drivers and dispatchers both need
-- to know the currency to display amounts correctly.

create table if not exists public.app_settings (
  id boolean primary key default true check (id),
  currency text not null default 'GHS',
  updated_at timestamptz not null default now()
);

insert into public.app_settings (id, currency)
values (true, 'GHS')
on conflict (id) do nothing;

comment on table public.app_settings is 'Single-row app-wide settings (currently just the payment currency). Singleton enforced by the boolean primary key.';

drop trigger if exists app_settings_set_updated_at on public.app_settings;
create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function public.set_updated_at();

alter table public.app_settings enable row level security;

drop policy if exists "app_settings: any authenticated read" on public.app_settings;
create policy "app_settings: any authenticated read"
  on public.app_settings for select
  using (auth.uid() is not null);

drop policy if exists "app_settings: super admin update" on public.app_settings;
create policy "app_settings: super admin update"
  on public.app_settings for update
  using (public.is_super_admin())
  with check (public.is_super_admin());

alter publication supabase_realtime add table public.app_settings;
