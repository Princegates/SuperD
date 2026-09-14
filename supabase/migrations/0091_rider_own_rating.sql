-- SuperDelivery: let a rider see how they are rated.
--
-- Until now only dispatch could read delivery_ratings at all ("dispatcher
-- reads all", 0034), so a rider had no way to know their own score - the
-- one number the platform judges them on, invisible to them.
--
-- WHY A FUNCTION AND NOT A POLICY
--
-- The obvious fix is a `driver_id = auth.uid()` select policy, which would
-- make the existing driver_rating_summary() work for riders unchanged. It
-- would also hand them every individual row, including the customer's
-- free-text comment.
--
-- Those comments are written on a public tracking page by someone the
-- rider just delivered to, and who is identifiable from the delivery they
-- are attached to. A customer who writes "he was rude" is telling the
-- business, not opening a conversation with the rider at their door. So
-- the rider gets the score and the shape of it; dispatch keeps the words.
--
-- Hence: security definer, scoped to auth.uid() and nobody else, returning
-- aggregates only. There is no parameter to point it at another rider.

create or replace function public.my_rating_summary()
returns table (
  average numeric,
  ratings_count bigint,
  five_star bigint,
  four_star bigint,
  three_star bigint,
  two_star bigint,
  one_star bigint
)
language sql
security definer
set search_path = public
stable
as $$
  select
    round(avg(r.rating)::numeric, 2),
    count(*),
    count(*) filter (where r.rating = 5),
    count(*) filter (where r.rating = 4),
    count(*) filter (where r.rating = 3),
    count(*) filter (where r.rating = 2),
    count(*) filter (where r.rating = 1)
  from public.delivery_ratings r
  where r.driver_id = auth.uid();
$$;

revoke all on function public.my_rating_summary() from public;
grant execute on function public.my_rating_summary() to authenticated;

comment on function public.my_rating_summary() is 'A rider''s own rating, aggregates only - no customer comments, which stay with dispatch (see 0091). Scoped to auth.uid() with no parameter, so it cannot be pointed at anyone else.';
