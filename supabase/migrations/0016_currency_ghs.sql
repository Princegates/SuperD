-- SuperD: switch the default/existing payment currency from USD to GHS
-- (Ghana cedi). This is a self-hosted, single-tenant instance running in
-- Ghana - every payment recorded so far is really in cedis, it just used
-- the placeholder default from 0003_payments.sql. Existing rows still
-- carrying that placeholder are corrected too, not just new ones.

alter table public.payments alter column currency set default 'GHS';

update public.payments set currency = 'GHS' where currency = 'USD';
