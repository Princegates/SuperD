import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver_notice.dart';

class DriverNoticeRepository {
  DriverNoticeRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'driver_notices';

  /// Every notice relevant to the signed-in driver - broadcasts and their
  /// own targeted ones - live, so a new promotion/message shows up on
  /// their dashboard without a restart. No explicit filter needed here:
  /// Supabase Realtime already scopes a stream to whatever RLS allows the
  /// authenticated caller to see (active, unexpired, broadcast-or-theirs
  /// - see the policy in `0046_driver_notices.sql`). Dismissed ones are
  /// filtered client-side (see [DriverNotice.isDismissedBy]) rather than
  /// by RLS, so dismissing one doesn't drop it out of the stream entirely
  /// - just stops it being rendered.
  Stream<List<DriverNotice>> watchVisibleNotices() {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DriverNotice.fromMap).toList());
  }

  /// Every notice ever created, regardless of audience/status - the raw
  /// data behind Console > Notices, so a dispatcher can review what's
  /// been sent (including inactive/expired ones).
  Future<List<DriverNotice>> fetchAll() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return rows.map(DriverNotice.fromMap).toList();
  }

  /// Posts a new notice - [targetDriverId] null means every driver sees
  /// it (a broadcast/promotion); set means only that one driver does (a
  /// direct message). Only takes effect if the caller is a dispatcher or
  /// super admin - enforced by RLS, not just this client.
  Future<void> create({
    required String title,
    required String body,
    String? targetDriverId,
    DateTime? expiresAt,
  }) async {
    await _client.from(_table).insert({
      'title': title,
      'body': body,
      'target_driver_id': targetDriverId,
      'created_by': _client.auth.currentUser?.id,
      'expires_at': expiresAt?.toIso8601String(),
    });
  }

  /// Ends a notice early without deleting it - it stops showing to
  /// drivers immediately, but stays in the Console's history.
  Future<void> deactivate(String id) async {
    await _client.from(_table).update({'is_active': false}).eq('id', id);
  }

  /// Permanently removes a notice.
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  /// The signed-in driver closes a notice for themselves - see
  /// `dismiss_driver_notice()`. Safe to call on a notice already
  /// dismissed (a no-op) or one that isn't theirs (RLS/the function's own
  /// check rejects it silently rather than erroring the driver's UI).
  Future<void> dismiss(String noticeId) async {
    await _client.rpc(
      'dismiss_driver_notice',
      params: {'p_notice_id': noticeId},
    );
  }
}
