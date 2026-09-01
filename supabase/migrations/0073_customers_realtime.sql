-- SuperD: the Customers directory screen streams public.customers
-- (CustomerRepository.watchAll(), Console > Customers, super-admin-only)
-- via Supabase Realtime, but the table was never added to the
-- supabase_realtime publication when it was created in
-- 0055_customer_directory.sql. Postgres only broadcasts row changes for
-- tables in that publication - without it, .stream() can't open the
-- channel at all, which is why this fails outright (a
-- RealtimeSubscribeException/channelError on every visit) rather than
-- just missing live updates the way commission_payments did before
-- 0071_commission_payments_realtime.sql (same root cause, worse
-- symptom - `customers` has no initial-snapshot fallback since the
-- subscribe itself never succeeds).

alter publication supabase_realtime add table public.customers;
