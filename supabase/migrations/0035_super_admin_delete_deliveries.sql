-- SuperD: deleting a delivery record outright (as opposed to cancelling
-- it, which keeps the record but marks it 'cancelled') was already
-- possible for any dispatcher at the RLS level since 0002 - just never
-- exposed anywhere in the app. Restricts that to a super admin only (a
-- dispatcher can still cancel, just not permanently erase the record)
-- and that's what the Console now actually offers a button for.
--
-- Related records behave the same as before: delivery_status_history,
-- payments, and delivery_ratings disappear along with the delivery (on
-- delete cascade, already the case for all three); commission_payments
-- and sms_log rows stay, with delivery_id set to null (on delete set
-- null, already the case) - those ledgers outlive the delivery they
-- were about.

drop policy if exists "deliveries: dispatcher delete" on public.deliveries;
create policy "deliveries: super admin delete"
  on public.deliveries for delete
  using (public.is_super_admin());
