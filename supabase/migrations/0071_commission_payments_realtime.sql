-- SuperD: a driver's commission balance wasn't clearing from the dashboard
-- the moment a daily-fee/commission payment went through - only after a
-- full log-out/log-in.
--
-- Root cause: commission_payments (0029_commission_payments.sql) was never
-- added to the supabase_realtime publication, unlike driver_daily_fees
-- (see 0031_driver_daily_fee.sql). CommissionRepository.watchDueForDriver()
-- opens a Postgres changes stream on this table (see
-- lib/data/repositories/commission_repository.dart), but Postgres only
-- ever broadcasts row changes for tables in that publication - without it,
-- .stream() returns just its one initial snapshot and then goes silent,
-- no error either. paystack-daily-fee-webhook settles due commission rows
-- via an admin (service-role) UPDATE once Paystack confirms payment - that
-- write was always invisible to the driver's already-open subscription,
-- explaining why nothing changed on-screen until the app restarted and
-- fetched a fresh snapshot.

alter publication supabase_realtime add table public.commission_payments;
