-- SuperD: lets the new Console > System Health tab show something real
-- about the two operational tables that exist today but have never had
-- any admin visibility - rate_limit_hits (0058_public_form_rate_limiting.sql)
-- and road_distance_cache (0094_road_distance_cache.sql).
--
-- Both tables have RLS enabled with zero policies for anon/authenticated
-- - the only thing that can read them at all is a SECURITY DEFINER
-- function, which bypasses RLS entirely. That means the internal
-- `is_super_admin()` check below is not a nice-to-have, it is the only
-- access control standing between any authenticated account (a driver
-- included) and these rows - mirrored verbatim from erase_customer()
-- (0082_erase_customer.sql), the existing precedent for this pattern.
--
-- Both return aggregates only, never raw rows - there's no legitimate
-- reason for a dashboard to see an individual rate-limit hit's key
-- (a phone number or IP) or an individual cached route's coordinates.

create or replace function public.get_rate_limit_summary()
returns table (
  action text,
  hits_last_hour bigint,
  hits_last_24h bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can view rate-limit stats.';
  end if;

  return query
    select
      r.action,
      count(*) filter (where r.created_at > now() - interval '1 hour') as hits_last_hour,
      count(*) filter (where r.created_at > now() - interval '24 hours') as hits_last_24h
    from public.rate_limit_hits r
    where r.created_at > now() - interval '24 hours'
    group by r.action
    order by r.action;
end;
$$;

revoke all on function public.get_rate_limit_summary() from public, anon, authenticated;
grant execute on function public.get_rate_limit_summary() to authenticated;

comment on function public.get_rate_limit_summary() is 'Aggregate rate-limit hit counts per action over the last hour/24h, for Console > System Health. Super admin only (checked internally - see comment above). Never returns the underlying key (phone/IP).';

create or replace function public.get_road_distance_cache_stats()
returns table (
  total_routes bigint,
  routes_added_last_24h bigint,
  total_hits bigint,
  avg_hits_per_route numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can view cache stats.';
  end if;

  return query
    select
      count(*)::bigint as total_routes,
      count(*) filter (where c.created_at > now() - interval '24 hours')::bigint as routes_added_last_24h,
      coalesce(sum(c.hits), 0)::bigint as total_hits,
      coalesce(round(avg(c.hits), 2), 0) as avg_hits_per_route
    from public.road_distance_cache c;
end;
$$;

revoke all on function public.get_road_distance_cache_stats() from public, anon, authenticated;
grant execute on function public.get_road_distance_cache_stats() to authenticated;

comment on function public.get_road_distance_cache_stats() is 'Aggregate road-distance cache stats (size, growth, hit volume) for Console > System Health. Super admin only (checked internally). Never returns individual routes/coordinates.';
