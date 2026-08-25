import 'payment_method.dart';
import 'payment_status.dart';

class Payment {
  final String id;
  final String deliveryId;
  final double amount;
  final String currency;
  final PaymentMethod method;
  final PaymentStatus status;
  final String? gatewayReference;
  final String? notes;
  final String? recordedBy;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Payment({
    required this.id,
    required this.deliveryId,
    required this.amount,
    required this.currency,
    required this.method,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.gatewayReference,
    this.notes,
    this.recordedBy,
    this.paidAt,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.parse(v as String);

    return Payment(
      id: map['id'] as String,
      deliveryId: map['delivery_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'USD',
      method: PaymentMethod.fromString(map['method'] as String? ?? 'cash'),
      status: PaymentStatus.fromString(map['status'] as String? ?? 'pending'),
      gatewayReference: map['gateway_reference'] as String?,
      notes: map['notes'] as String?,
      recordedBy: map['recorded_by'] as String?,
      paidAt: parseDate(map['paid_at']),
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: parseDate(map['updated_at']) ?? DateTime.now(),
    );
  }
}
