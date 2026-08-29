-- SuperD: replaces Hubtel with Paystack as the driver daily-fee Mobile
-- Money gateway (0031_driver_daily_fee.sql originally wired up Hubtel).
-- Renames the two gateway-specific columns to generic names now that
-- there's a new gateway behind them, and updates payment_method's allowed
-- values. The manual-reference fallback (a driver pays the business's
-- MoMo number directly and submits the transaction reference for a
-- dispatcher to confirm) is untouched - it never depended on which
-- real-time gateway was in use.

-- Relabel any existing rows BEFORE tightening the constraint below - the
-- constraint would otherwise reject stale 'hubtel_momo' rows the instant
-- it's added, since check constraints validate existing data immediately.
update public.driver_daily_fees
set payment_method = 'paystack'
where payment_method = 'hubtel_momo';

alter table public.driver_daily_fees
  drop constraint if exists driver_daily_fees_payment_method_check,
  add constraint driver_daily_fees_payment_method_check
    check (payment_method in ('paystack', 'manual'));

alter table public.driver_daily_fees
  rename column hubtel_client_reference to payment_reference;

alter table public.driver_daily_fees
  rename column hubtel_transaction_id to payment_transaction_id;

comment on column public.driver_daily_fees.payment_reference is 'The unique reference we generated and sent to Paystack when starting a real-time charge - how paystack-daily-fee-webhook matches its callback back to this row. Null for a manual/waived row.';
comment on column public.driver_daily_fees.payment_transaction_id is 'Paystack''s own transaction id for a real-time charge, once known - purely for cross-referencing against the Paystack dashboard if a payment needs investigating. Null for a manual/waived row.';
