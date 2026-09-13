-- SuperD: riders move from a tiered daily fee to a flat 12% of each
-- delivery's fare, matching what superdeliverygh.com now advertises
-- ("You keep 88% of every fare ... no daily fee, no joining cost, and
-- nothing owed on a day you do not ride").
--
-- No machinery changes here, because none is needed. Percentage
-- commission already exists (`commission_percentage`,
-- 0066_commission_percentage.sql): log_commission_due() writes one
-- commission_payments row per delivered job worth
-- `commission_flat_fee + payments_total * commission_percentage / 100`.
-- The daily fee is resolved entirely from `driver_daily_fee_tiers`
-- (driver_daily_fee_amount() in 0037_tiered_daily_fee.sql returns
-- coalesce(matching tier, 0)), so emptying that table is what switches
-- the daily fee off. (There is no `app_settings.driver_daily_fee` left
-- to clear: 0037 dropped that column when tiers replaced it.)
--
-- Settlement is unaffected and needs no new flow: a driver still pays
-- through the same sheet, which charges driver_total_amount_due() =
-- driver_daily_fee_balance() + driver_commission_due_amount()
-- (0050_bundle_commission_with_daily_fee.sql). With no tiers the first
-- term is 0, so that one payment now settles commission alone. The
-- assignment gate likewise degrades to the right thing: driver_daily_fee_paid()
-- reads a 0 balance as clear, leaving driver_has_overdue_commission()
-- (0067_daily_commission_settlement.sql) as the only block - commission
-- left due from a *previous* day, which is exactly the promise above.

update public.app_settings
set commission_percentage = 12,
    commission_flat_fee = 0,
    driver_commission_enabled = true,
    -- Free days were a daily-fee concept: a threshold of completed
    -- deliveries earned a day with no fee to pay. With no fee there is
    -- nothing for a free day to excuse.
    free_day_delivery_threshold = null;

-- The daily fee itself. Emptying this is the switch; anything left here
-- would keep charging riders a day rate the site says they do not pay.
-- To reinstate one later, Console > Daily fees writes this table, or:
--   insert into public.driver_daily_fee_tiers (min_deliveries, amount)
--   values (0, 10);
delete from public.driver_daily_fee_tiers;

comment on column public.app_settings.commission_percentage is 'Percentage of a completed delivery''s recorded payment amount the driver owes the business, added to commission_flat_fee to make up the single amount due row created by log_commission_due(). Set to 12 in 0085_flat_twelve_percent_commission.sql, which is the rate superdeliverygh.com advertises; the daily-fee tiers were emptied in the same migration, so this is now the only thing a rider pays.';
