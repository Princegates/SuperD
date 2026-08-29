import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/customer.dart';
import '../../models/delivery.dart';
import '../../shared/utils/resilient_stream.dart';

class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'customers';

  /// Every customer on file, newest-updated first. RLS limits this to a
  /// super admin - a dispatcher or auditor querying it gets an empty list
  /// back, not an error, same as `audit_log` before an auditor could read
  /// it - see `0055_customer_directory.sql`.
  Stream<List<Customer>> watchAll() {
    return resilientRealtimeStream(
      () => _client
          .from(_table)
          .stream(primaryKey: ['id'])
          .order('updated_at', ascending: false)
          .map((rows) => rows.map(Customer.fromMap).toList()),
    );
  }

  /// Every delivery this customer (by phone) has ever placed, newest
  /// first - for the customer-service detail view. Relies on the caller
  /// already having read access to `deliveries` (a super admin does).
  Future<List<Delivery>> fetchDeliveryHistory(String phone) async {
    final rows = await _client
        .from('deliveries')
        .select()
        .eq('customer_phone', phone)
        .order('created_at', ascending: false);
    return rows.map(Delivery.fromMap).toList();
  }
}
