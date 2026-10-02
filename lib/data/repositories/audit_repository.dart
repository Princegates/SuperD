import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/audit_log_entry.dart';

/// Read side of the audit log - RLS only lets a super admin actually see
/// any rows back, regardless of who's signed in. Writing goes through the
/// `logAuditEvent` fire-and-forget helper instead, called right after each
/// meaningful action across the app.
class AuditRepository {
  AuditRepository(this._client);

  final SupabaseClient _client;

  /// [before] pages further back in time - pass the last entry's
  /// `createdAt` from the previous page to continue past it, or leave it
  /// null for the most recent page. A keyset cursor rather than
  /// `.range()`'s numeric offset, so a row inserted between two page
  /// reads can't shift the next page's contents or duplicate/skip a row.
  Future<List<AuditLogEntry>> fetchRecent({
    int limit = 200,
    DateTime? before,
  }) async {
    var query = _client.from('audit_log').select();
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(AuditLogEntry.fromMap).toList();
  }
}
