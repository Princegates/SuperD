import 'package:supabase_flutter/supabase_flutter.dart';

/// Records one row in the super-admin audit log via the `log_audit_event`
/// database function - fire-and-forget, since a logging failure should
/// never interrupt (or roll back) the action that triggered it.
Future<void> logAuditEvent(
  SupabaseClient client, {
  required String action,
  required String entityType,
  String? entityId,
  required String summary,
}) async {
  try {
    await client.rpc(
      'log_audit_event',
      params: {
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'summary': summary,
      },
    );
  } catch (_) {
    // Best-effort only - see the doc comment above.
  }
}
