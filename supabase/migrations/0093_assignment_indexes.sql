-- SuperD: indexes for automatic driver matching.
--
-- `profiles` has had no indexes at all until now, so every driver-matching
-- run sequentially scanned the whole table. That was invisible at a dozen
-- riders and stops being invisible somewhere around a hundred, because
-- matching sits on the critical path of every new order - see
-- submit_delivery_request() (latest definition in 0077), and the same
-- block in driver_cancel_delivery() (0078) and
-- assign_pending_on_driver_location() (0061).
--
-- Indexes only. No function is redefined here on purpose: the matching
-- logic is correct, it was just being executed the expensive way, and
-- three large plpgsql functions that have been amended across a dozen
-- migrations are not worth the risk of a retype for a cost the planner
-- can fix on its own.
--
-- The haversine ORDER BY itself stays unindexable - no btree can order by
-- distance from a point that changes per call. It does not need to be:
-- once the predicate below is served by an index, the planner sorts the
-- online riders (~100) rather than every profile ever created, and
-- sorting a hundred rows costs nothing.
--
-- These are plain CREATE INDEX, not CONCURRENTLY, because a migration
-- runs in a transaction and CONCURRENTLY cannot. At this table's size
-- that is a sub-second lock. If profiles ever reaches millions of rows,
-- build future indexes outside a migration with CONCURRENTLY instead.

-- The matching predicate, minus the freshness window - now() is not
-- immutable so it cannot live in the index, but ordering the index by
-- location_updated_at lets that comparison be served as a range scan
-- over an already-small set.
create index if not exists profiles_assignable_driver_idx
  on public.profiles (location_updated_at desc)
  where role = 'driver'
    and is_active
    and not is_frozen
    and is_online
    and last_lat is not null
    and last_lng is not null;

-- The Live Map, the Drivers roster and the Console's ranking hints all
-- filter profiles by role before anything else.
create index if not exists profiles_role_idx on public.profiles (role);

-- The per-candidate "how many live jobs is this rider already carrying?"
-- subquery inside the matching block. This is the one that made matching
-- quadratic: a count per candidate driver, each one previously scanning
-- deliveries by driver and filtering status afterwards.
-- deliveries_assigned_driver_idx (0001) covers the driver but not the
-- status, so every one of that rider's historical jobs was still read.
-- Partial, so the index holds only live work - a few hundred rows, not
-- the whole delivery history - and stays that size as the table grows.
create index if not exists deliveries_driver_active_idx
  on public.deliveries (assigned_driver_id)
  where status not in ('delivered', 'cancelled');

analyze public.profiles;
analyze public.deliveries;
