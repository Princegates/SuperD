import 'daily_fee_status.dart';

/// One driver's payment/waiver attempt toward a single calendar day's
/// tiered platform fee - see `driver_daily_fees` in
/// `0031_driver_daily_fee.sql` and `0037_tiered_daily_fee.sql`. A driver
/// can have more than one row for the same day now (a top-up after
/// crossing into a higher tier); no rows at all for a given day means
/// nothing has been paid toward it yet.
class DriverDailyFee {
  final String id;
  final String driverId;
  final DateTime feeDate;
  final double amount;
  final String currency;
  final DailyFeeStatus status;
  final String? paymentMethod;
  final String? hubtelClientReference;
  final String? hubtelTransactionId;
  final String? manualReference;
  final String? confirmedBy;
  final DateTime? paidAt;
  final DateTime createdAt;

  const DriverDailyFee({
    required this.id,
    required this.driverId,
    required this.feeDate,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.paymentMethod,
    this.hubtelClientReference,
    this.hubtelTransactionId,
    this.manualReference,
    this.confirmedBy,
    this.paidAt,
  });

  factory DriverDailyFee.fromMap(Map<String, dynamic> map) {
    return DriverDailyFee(
      id: map['id'] as String,
      driverId: map['driver_id'] as String,
      feeDate: DateTime.parse(map['fee_date'] as String),
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'GHS',
      status: DailyFeeStatus.fromString(map['status'] as String? ?? 'pending'),
      paymentMethod: map['payment_method'] as String?,
      hubtelClientReference: map['hubtel_client_reference'] as String?,
      hubtelTransactionId: map['hubtel_transaction_id'] as String?,
      manualReference: map['manual_reference'] as String?,
      confirmedBy: map['confirmed_by'] as String?,
      paidAt: map['paid_at'] == null
          ? null
          : DateTime.parse(map['paid_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  bool get isCleared =>
      status == DailyFeeStatus.paid || status == DailyFeeStatus.waived;
}
