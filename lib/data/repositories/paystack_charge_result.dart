/// The outcome of starting or continuing a Paystack Mobile Money charge -
/// shared by [DriverDailyFeeRepository]'s and [VendorRepository]'s
/// charge/OTP-submit methods, since both go through the same Paystack
/// Charge API shape. [status] is one of Paystack's own charge statuses
/// ('pending' covers both `pay_offline` and `success`, since either way
/// the row settles via `paystack-daily-fee-webhook`); [reference] is only
/// set when [status] is `'send_otp'`, identifying which attempt a
/// submitted code belongs to.
typedef PaystackChargeResult = ({
  String status,
  String message,
  String? reference,
});
