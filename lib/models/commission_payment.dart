import 'commission_status.dart';

/// One completed delivery's commission - a flat fee, a percentage of the
/// delivery's payment amount, or both, added together into the single
/// amount a driver owes the business - created automatically when the
/// delivery is marked delivered (see `log_commission_due()` in
/// `0029_commission_payments.sql`, `0066_commission_percentage.sql`).
class CommissionPayment {
  final String id;
  final String driverId;
  final String? deliveryId;
  final double amount;
  final String currency;
  final CommissionStatus status;
  final DateTime? paidAt;
  final DateTime createdAt;

  const CommissionPayment({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.deliveryId,
    this.paidAt,
  });

  factory CommissionPayment.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.parse(v as String);

    return CommissionPayment(
      id: map['id'] as String,
      driverId: map['driver_id'] as String,
      deliveryId: map['delivery_id'] as String?,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'GHS',
      status: CommissionStatus.fromString(map['status'] as String? ?? 'due'),
      paidAt: parseDate(map['paid_at']),
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
    );
  }
}
