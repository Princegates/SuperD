-- Fixes "Add vendor" (and public vendor signup) failing outright with a
-- PostgREST 300 "Multiple Choices" response - PostgREST's specific error
-- when it finds more than one function matching an RPC call by name and
-- can't tell which one you meant.
--
-- Root cause: 0059_public_form_captcha_gate.sql added a new trailing
-- p_client_ip parameter to register_vendor() via `create or replace
-- function` - but CREATE OR REPLACE only replaces a function with the
-- exact same parameter list; adding a parameter creates a brand new,
-- separate overload instead (silently - no error), leaving the old
-- 7-argument version (from 0027_separate_vendor_orders_code.sql) still
-- sitting in the database. 0059 revoked anon's execute grant on that old
-- signature (line 37 of that file) but never dropped the function itself,
-- so it kept existing - invisible until an actual ambiguous call finally
-- surfaced it here. Every migration since (0072, 0074) correctly used
-- `create or replace` against the newer 8-argument signature, so they
-- never noticed the older one was still there.
--
-- This is safe to run even if the stale overload was already manually
-- dropped (e.g. via the SQL Editor) - `if exists` makes it a no-op then.
drop function if exists public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid
);
