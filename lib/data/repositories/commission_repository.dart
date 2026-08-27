import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/commission_payment.dart';
import '../../models/commission_status.dart';

class CommissionRepository {
  CommissionRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'commission_payments';

  /// Every commission record ever created, for the super-admin Console's
  /// Commission tab - RLS already limits this to dispatchers/super admins.
  /// Rows are created automatically (see `log_commission_due()` in
  /// `0029_commission_payments.sql`) - there's no manual "add" here.
  Future<List<CommissionPayment>> fetchAll() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return rows.map(CommissionPayment.fromMap).toList();
  }

  Future<void> updateStatus({
    required String commissionId,
    required CommissionStatus status,
  }) async {
    await _client
        .from(_table)
        .update({
          'status': status.wireValue,
          'paid_at': status == CommissionStatus.paid
              ? DateTime.now().toIso8601String()
              : null,
          'marked_paid_by': status == CommissionStatus.paid
              ? _client.auth.currentUser?.id
              : null,
        })
        .eq('id', commissionId);
  }
}
