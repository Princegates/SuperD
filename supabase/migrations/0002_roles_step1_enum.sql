-- SuperD: three-tier roles - STEP 1 of 2.
--
-- Run this file FIRST, on its own, and let it finish before running
-- 0002_roles_step2_policies.sql. Postgres will not let a brand-new enum
-- value be used anywhere (even inside a function body) in the same
-- transaction that created it - running these two files separately is
-- what avoids that "unsafe use of new value" error.

alter type public.user_role rename value 'admin' to 'dispatcher';
alter type public.user_role add value if not exists 'super_admin';
