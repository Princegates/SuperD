-- SuperD: lets the marketing site read the rider commission rate, so the
-- rate becomes a thing a super admin changes in Console > Settings rather
-- than a number typed into a web page. Before this, superdeliverygh.com
-- had "12%" hard-coded in six places, and changing the real rate silently
-- made our own advertising wrong.
--
-- app_settings itself stays shut to anonymous readers - its RLS is
-- "any authenticated read" (0017_app_settings.sql) and that does not
-- change here. This is deliberately not a view over the table and not a
-- widened policy: it is one function returning the three values a public
-- page has any business knowing, so support_phone, admin_alert_email,
-- admin_alert_phone and everything else on that row stay unreadable.
--
-- The numbers it does return are ones we publish on purpose: the whole
-- point is to print them on a page anyone can load.

create or replace function public.public_rider_terms()
returns table (
  commission_percentage numeric,
  commission_flat_fee numeric,
  currency text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    -- The master switch wins. With commission off a rider owes nothing,
    -- so the honest public answer is 0 rather than the dormant setting.
    case when coalesce(s.driver_commission_enabled, true)
         then coalesce(s.commission_percentage, 0) else 0 end,
    case when coalesce(s.driver_commission_enabled, true)
         then coalesce(s.commission_flat_fee, 0) else 0 end,
    coalesce(s.currency, 'GHS')
  from public.app_settings s
  limit 1;
$$;

-- Execute defaults to PUBLIC on a new function; name the callers instead.
revoke all on function public.public_rider_terms() from public;
grant execute on function public.public_rider_terms() to anon, authenticated;

comment on function public.public_rider_terms() is 'The rider-facing commission terms, readable without signing in, so superdeliverygh.com can print the live rate instead of a hard-coded one. Returns 0 for both amounts while driver_commission_enabled is false. Exposes only these three values - app_settings stays authenticated-read (0017_app_settings.sql).';
