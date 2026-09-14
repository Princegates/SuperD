-- SuperD: precheck + rate limit for submitting a vendor subscription
-- charge's one-time code - see paystack-vendor-subscription-charge's
-- send_otp case and the new paystack-vendor-subscription-submit-otp
-- function. Same shape as charge_vendor_subscription_precheck() in
-- 0074_vendor_subscriptions.sql: this is a PUBLIC, no-login endpoint (a
-- vendor only has their own code), so without a rate limit here an
-- attacker could brute-force a one-time code as many times as they like
-- against Paystack using someone else's in-flight charge attempt.

create or replace function public.submit_vendor_subscription_otp_precheck(
  p_code text,
  p_reference text,
  p_client_ip text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vendors%rowtype;
begin
  select * into v from public.vendors where code = p_code;
  if not found then
    raise exception 'Vendor not found';
  end if;

  if v.subscription_paid_at is not null or v.is_active then
    raise exception 'This payment has already gone through.';
  end if;
  if v.subscription_payment_reference is distinct from p_reference then
    raise exception 'This payment attempt is no longer active. Please try again.';
  end if;

  perform public.enforce_rate_limit(
    'code:' || p_code, 'vendor_subscription_otp', 8, interval '1 hour'
  );
  perform public.enforce_rate_limit(
    'ip:' || coalesce(p_client_ip, public.request_ip()),
    'vendor_subscription_otp', 15, interval '1 hour'
  );

  return v.id;
end;
$$;

comment on function public.submit_vendor_subscription_otp_precheck(text, text, text) is 'Public. Validates a vendor subscription OTP-submit attempt (matching code+reference, not already paid/active) and rate-limits it before paystack-vendor-subscription-submit-otp forwards the code to Paystack. Returns the vendor id.';
