import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/audit_log_entry.dart';

/// Read side of the audit log - RLS only lets a super admin actually see
/// any rows back, regardless of who's signed in. Writing goes through the
/// `logAuditEvent` fire-and-forget helper instead, called right after each
/// meaningful action across the app.
class AuditRepository {
  AuditRepository(this._client);

  final SupabaseClient _client;

  Future<List<AuditLogEntry>> fetchRecent({int limit = 200}) async {
    final rows = await _client
        .from('audit_log')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AuditLogEntry.fromMap).toList();
  }
}
