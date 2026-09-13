-- SuperD: a driver's average rating, aggregated in the database rather
-- than by shipping every rating row to the client.
--
-- `delivery_ratings` has existed since 0034 and dispatchers have always
-- been allowed to read it ("delivery_ratings: dispatcher reads all"), but
-- nothing ever did - customers have been rating drivers into a table no
-- one looks at. This is the read side of fixing that.
--
-- Deliberately NOT security definer. As a plain invoker-rights function
-- the RLS policy on delivery_ratings still applies, so this returns rows
-- to a dispatcher or above and nothing at all to anyone else - the same
-- boundary as reading the table directly, with none of the transfer.

create or replace function public.driver_rating_summary()
returns table (
  driver_id uuid,
  average numeric,
  ratings_count bigint
)
language sql
stable
set search_path = public
as $$
  select r.driver_id,
         round(avg(r.rating)::numeric, 2),
         count(*)
  from public.delivery_ratings r
  group by r.driver_id;
$$;

grant execute on function public.driver_rating_summary() to authenticated;

comment on function public.driver_rating_summary() is 'Average rating and rating count per driver, from delivery_ratings (0034). Invoker rights on purpose: the table''s "dispatcher reads all" RLS policy governs it, so a driver or anonymous caller gets an empty set.';
