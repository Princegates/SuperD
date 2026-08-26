import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/audit_log_entry.dart';
import '../../../models/payment.dart';

/// Every payment ever recorded - the raw data behind the Console's Finance
/// tab. Aggregation (totals by status/method/etc) happens in the tab
/// itself rather than here, since it's cheap and there's only one
/// consumer so far.
final allPaymentsProvider = FutureProvider<List<Payment>>((ref) {
  return ref.watch(paymentRepositoryProvider).fetchAll();
});

/// The most recent audit log entries - only resolves any rows for a
/// super admin, since RLS hides everything from anyone else.
final auditLogProvider = FutureProvider<List<AuditLogEntry>>((ref) {
  return ref.watch(auditRepositoryProvider).fetchRecent();
});
