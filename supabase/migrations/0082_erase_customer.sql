-- SuperD: lets a super admin actually erase a customer's personal data,
-- not just remove them from the directory - see kPolicySections' "Your
-- rights over your data" in superd_legal_policy.dart, which promises a
-- deletion right under Ghana's Data Protection Act, 2012 (Act 843).
--
-- `public.customers` (0055_customer_directory.sql) is only ever a
-- derived read view rebuilt from `deliveries` on every insert - deleting
-- a row there alone does nothing lasting, since the customer's real
-- name/phone/email still live on every one of their delivery rows and
-- the directory entry comes straight back the next time that phone
-- places an order. This scrubs the source instead: every delivery the
-- phone number appears on has its customer_name/customer_phone/
-- customer_email cleared, then the now-stale directory row is removed.
-- Pickup/dropoff addresses, pricing, and payment history are left
-- alone - that's operational/accounting record the same policy says we
-- may keep, not personal contact information.
--
-- Blocked while any of the customer's deliveries are still in progress
-- (not yet 'delivered' or 'cancelled'): a driver mid-delivery still
-- needs a working phone number and name to actually complete the job.
-- The same shape as vendor deletion being blocked by delivery history -
-- finish or cancel first, then erase.

create or replace function public.erase_customer(p_phone text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := trim(p_phone);
  v_active_count integer;
  v_erased_count integer;
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can erase a customer.';
  end if;

  if v_phone is null or v_phone = '' then
    raise exception 'A phone number is required.';
  end if;

  select count(*) into v_active_count
  from public.deliveries
  where customer_phone = v_phone
    and status not in ('delivered', 'cancelled');

  if v_active_count > 0 then
    raise exception
      'This customer has % delivery(ies) still in progress - wait until '
      'they are delivered or cancelled before erasing.',
      v_active_count;
  end if;

  update public.deliveries
  set customer_name = 'Deleted customer',
      customer_phone = null,
      customer_email = null
  where customer_phone = v_phone;

  get diagnostics v_erased_count = row_count;

  delete from public.customers where phone = v_phone;

  return v_erased_count;
end;
$$;

comment on function public.erase_customer(text) is 'Super-admin only. Scrubs customer_name/customer_phone/customer_email from every delivery for this phone number and removes the customers directory row. Blocked if any delivery for this phone is not yet delivered/cancelled. Returns the number of deliveries scrubbed.';

grant execute on function public.erase_customer(text) to authenticated;
