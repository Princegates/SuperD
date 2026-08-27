import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/payment.dart';
import '../../models/payment_method.dart';
import '../../models/payment_status.dart';

class PaymentRepository {
  PaymentRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'payments';

  /// The payment recorded for a delivery, if any. A delivery normally has
  /// at most one payment row (its expected fee), created alongside it.
  Stream<Payment?> watchForDelivery(String deliveryId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('delivery_id', deliveryId)
        .map((rows) => rows.isEmpty ? null : Payment.fromMap(rows.first));
  }

  /// Every payment ever recorded, for the super-admin Console's Finance
  /// tab - RLS already limits this to dispatchers/super admins.
  Future<List<Payment>> fetchAll() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return rows.map(Payment.fromMap).toList();
  }

  Future<void> recordPayment({
    required String deliveryId,
    required double amount,
    required PaymentMethod method,
    String currency = 'GHS',
    PaymentStatus status = PaymentStatus.pending,
  }) async {
    await _client.from(_table).insert({
      'delivery_id': deliveryId,
      'amount': amount,
      'currency': currency,
      'method': method.wireValue,
      'status': status.wireValue,
    });
  }

  Future<void> updateStatus({
    required String paymentId,
    required PaymentStatus status,
  }) async {
    await _client
        .from(_table)
        .update({'status': status.wireValue})
        .eq('id', paymentId);
  }
}
