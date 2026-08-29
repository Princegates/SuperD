-- SuperD: lets a driver see their own commission payment history (the
-- per-delivery flat fee - see `0029_commission_payments.sql`) from their
-- own app, same "driver reads own" treatment `driver_daily_fees` already
-- has (`0031_driver_daily_fee.sql`). Nothing else changes - dispatchers
-- keep full read/update access, and this table is still never writable
-- by a driver directly (rows only ever come from log_commission_due()).
--
-- `payments` needs no equivalent change: "payments: dispatcher or
-- assigned driver read" (0003_payments.sql) already lets a driver read
-- every payment recorded for a delivery assigned to them - which is what
-- backs their revenue history/today's-revenue count.

drop policy if exists "commission_payments: driver reads own" on public.commission_payments;
create policy "commission_payments: driver reads own"
  on public.commission_payments for select
  using (driver_id = auth.uid());
