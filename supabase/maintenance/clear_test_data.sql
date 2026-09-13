-- ===========================================================================
-- SuperDelivery: clear pre-launch test data
--
-- NOT A MIGRATION, and not something that has been run. It lives outside
-- supabase/migrations on purpose so nothing ever applies it
-- automatically, and as committed it deletes nothing at all - the scope in
-- STEP 1 is a placeholder that matches no real delivery. It only does
-- anything once someone edits that scope by hand and runs it in the
-- Supabase SQL editor deliberately.
--
-- WHAT IT IS FOR
--
-- Test orders left in production do not sit quietly. They are counted in
-- Console > Overview's completion rate, in the zone economics, in every
-- vendor's "deliveries sent", and in Finance's commission totals - so your
-- first real month is measured against orders that never happened. This
-- removes them.
--
-- WHAT IT DOES NOT DO
--
-- It never deletes an account. Not your super admin, not a dispatcher,
-- not a rider - there is no `delete from public.profiles` and no
-- `delete from auth.users` anywhere in this file, and none should be
-- added. Deleting your super admin would lock you out of the Console with
-- no way back in from the app, and STEP 4 checks the count is unchanged
-- to prove it did not happen. Accounts are people, not rows - see
-- "Riders and staff" at the bottom for the right way to retire one.
--
-- READ THIS BEFORE YOU RUN IT
--
-- Deletes are permanent and Supabase's daily backup may be older than the
-- data you are about to remove. Work in this order:
--
--   1. Edit the scope in STEP 1 to match what you actually want gone.
--   2. Run STEP 1 and STEP 2 on their own. They only read. Look at what
--      comes back and satisfy yourself it is all test data.
--   3. Only then run STEP 3.
--
-- The scope is defined once, in STEP 1, as a view every later step reads
-- from - so what you reviewed is exactly what gets deleted. Do not paste
-- a different WHERE clause into the delete steps.
--
-- A view rather than a temp table on purpose: the Supabase SQL editor
-- runs each press of Run over a pooled connection, and a temp table does
-- not reliably survive from one press to the next. STEP 5 drops it.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- STEP 1 - Say what counts as test data. EDIT THIS.
--
-- Three ways to choose, and you can combine them. Uncomment what you want
-- and delete the rest. The default is the safe one: nothing at all, so
-- running this file unedited deletes nothing.
-- ---------------------------------------------------------------------------
create or replace view public.test_data_scope as
select d.id, d.tracking_code, d.customer_name, d.status, d.created_at
from public.deliveries d
where
  -- (a) By tracking code. The most deliberate option, and the one to use
  --     if you have any real orders mixed in with the test ones.
  -- These are placeholders, not codes. A delivery whose tracking code
  -- is literally this does not exist, so the file as it stands deletes
  -- nothing.
  d.tracking_code in ('REPLACE-WITH-YOUR-TEST-TRACKING-CODES')

  -- (b) Everything raised before you opened for business. Uncomment and
  --     set the date to the morning of your launch day. Simple and
  --     usually right, provided no real customer got in early.
  -- or d.created_at < timestamptz '2026-10-01 00:00:00+00'

  -- (c) Everything from a specific test vendor.
  -- or d.vendor_id in (
  --   select id from public.vendors where vendor_name in ('Test Shop')
  -- )
;

select count(*) as deliveries_in_scope from public.test_data_scope;
select * from public.test_data_scope order by created_at;


-- ---------------------------------------------------------------------------
-- STEP 2 - What goes with them. Read-only.
--
-- Deleting a delivery already takes its payments, status history,
-- completion PIN, ratings and rejections with it (those foreign keys
-- cascade). Two things do NOT cascade and are handled explicitly in
-- STEP 3, because both would otherwise survive as figures in your
-- reports with nothing behind them:
--
--   * commission_payments - set to a null delivery_id, not deleted, so
--     test commission would keep counting as revenue in Finance.
--   * sms_log - the same, and it is what "SMS only on the first delivery"
--     reads to decide whether a customer has been texted before.
-- ---------------------------------------------------------------------------
select
  (select count(*) from public.payments
   where delivery_id in (select id from public.test_data_scope))          as payments,
  (select count(*) from public.commission_payments
   where delivery_id in (select id from public.test_data_scope))          as commission_rows,
  (select coalesce(sum(amount), 0) from public.commission_payments
   where delivery_id in (select id from public.test_data_scope))          as commission_value,
  (select count(*) from public.delivery_status_history
   where delivery_id in (select id from public.test_data_scope))          as history_rows,
  (select count(*) from public.delivery_ratings
   where delivery_id in (select id from public.test_data_scope))          as ratings,
  (select count(*) from public.delivery_completion_pins
   where delivery_id in (select id from public.test_data_scope))          as pins,
  (select count(*) from public.delivery_rejections
   where delivery_id in (select id from public.test_data_scope))          as rejections,
  (select count(*) from public.sms_log
   where delivery_id in (select id from public.test_data_scope))          as sms_rows;

-- The customer records these orders created. Kept separate because a
-- customer row is personal data and outlives any one delivery - see
-- "Customers" at the bottom.
select c.phone, c.full_name, c.email
from public.customers c
where c.phone in (select customer_phone from public.deliveries
                  where id in (select id from public.test_data_scope));


-- ---------------------------------------------------------------------------
-- STEP 3 - Delete. Permanent.
--
-- One transaction: either all of it goes or none of it does. Run this
-- only after STEP 1 and STEP 2 showed you what you expected.
-- ---------------------------------------------------------------------------
begin;

  -- Everything that refers to the deliveries goes first, and the
  -- deliveries themselves go last. The order is not cosmetic: the scope
  -- is a view over `deliveries`, so once those rows are gone the view is
  -- empty and any delete still to come would match nothing and quietly
  -- do nothing.

  -- This foreign key nulls rather than cascades - left alone, these
  -- become commission with no delivery behind it, still counted in
  -- Finance.
  delete from public.commission_payments
  where delivery_id in (select id from public.test_data_scope);

  delete from public.sms_log
  where delivery_id in (select id from public.test_data_scope);

  -- The audit trail refers to deliveries by id in a plain column with no
  -- foreign key at all, so these entries would otherwise survive pointing
  -- at nothing.
  delete from public.audit_log
  where entity_type = 'delivery'
    and entity_id in (select id from public.test_data_scope);

  -- Last. Takes payments, status history, PINs, ratings and rejections
  -- with it, by cascade.
  delete from public.deliveries
  where id in (select id from public.test_data_scope);

commit;


-- ---------------------------------------------------------------------------
-- STEP 4 - Check it took.
-- ---------------------------------------------------------------------------
select
  (select count(*) from public.deliveries)                          as deliveries_left,
  (select count(*) from public.payments)                            as payments_left,
  (select count(*) from public.commission_payments)                 as commission_left,
  (select count(*) from public.commission_payments
   where delivery_id is null)                                       as orphaned_commission,
  (select count(*) from public.delivery_status_history)             as history_left,
  -- Must be the same as before you started, and must not be 0. Nothing
  -- above deletes an account, so this is a check that stays true rather
  -- than one that could go either way - which is the point of running it.
  (select count(*) from public.profiles where role = 'super_admin')  as super_admins,
  (select count(*) from public.profiles)                             as accounts;

-- orphaned_commission should be 0. Anything above 0 is commission that
-- lost its delivery in some earlier deletion and is still being counted -
-- worth looking at before launch either way.


-- ---------------------------------------------------------------------------
-- STEP 5 - Put the scope view away, so it cannot be run against live data
-- by someone opening this file again months from now.
-- ---------------------------------------------------------------------------
drop view if exists public.test_data_scope;


-- ===========================================================================
-- Vendors
--
-- A test vendor has to lose its deliveries first (that foreign key does
-- not cascade), so run this after STEP 3, not before.
--
-- Prefer deactivating over deleting where you are unsure: an inactive
-- vendor cannot take new orders and stops appearing in the lists, and the
-- decision stays reversible.
--
--   update public.vendors set is_active = false
--   where vendor_name in ('Test Shop');
--
-- To remove one outright:
--
--   delete from public.vendors where vendor_name in ('Test Shop');
--
-- ===========================================================================
-- Customers
--
-- Customer records are keyed by phone number, not by a foreign key, so
-- deleting a delivery leaves the customer behind.
--
-- Do this from **Console > Customers**, not from here. `erase_customer()`
-- checks that a super admin is asking, and the SQL editor has no signed-in
-- user to be one - `auth.uid()` is null, so the function refuses with
-- "Only a super admin can erase a customer." That check is doing its job;
-- do not work around it by deleting the row by hand, because the function
-- also scrubs the customer's name, phone and email off the deliveries
-- themselves, and a plain delete would leave all of that behind.
--
-- ===========================================================================
-- Riders and staff
--
-- Never delete your own super admin account, from here or anywhere else.
-- It is the only role that can reach Console > Team to appoint another
-- one, so removing the last of them locks you out of your own system with
-- no route back in through the app - it would take a support ticket
-- against the database to recover.
--
-- Do not delete riders or dispatchers here either. A rider's profile is referenced by every
-- delivery they ever carried, every commission row, and every audit
-- entry, and most of those foreign keys refuse the delete rather than
-- cascading - so it either fails outright or, worse, takes real history
-- with it.
--
-- For a test rider account you are finished with:
--
--   update public.profiles set is_active = false, is_online = false
--   where email = 'testrider@example.com';
--
-- That is enough: they cannot log in, cannot be assigned, and do not
-- appear in the roster. If the account must genuinely disappear, delete
-- the auth user (Authentication > Users in the Supabase dashboard) once
-- it has no deliveries against it - the profile follows.
-- ===========================================================================
