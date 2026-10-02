import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/system_health.dart';

/// Thrown when a Console > System Health read fails, with a message safe
/// to show directly to a super admin.
class SystemHealthException implements Exception {
  SystemHealthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Read-only operational visibility for Console > System Health - every
/// method here is super-admin-only, enforced server-side (the
/// `admin-integration-status` Edge Function checks the caller's role
/// directly; the two RPCs each guard themselves with an internal
/// `is_super_admin()` check - see `0099_rate_limit_and_cache_admin_stats.sql`).
/// A dispatcher/auditor calling any of these gets a clean 403/exception,
/// never data.
class SystemHealthRepository {
  SystemHealthRepository(this._client);

  final SupabaseClient _client;

  Future<IntegrationStatus> fetchIntegrationStatus() async {
    try {
      final response = await _client.functions.invoke(
        'admin-integration-status',
      );
      return IntegrationStatus.fromMap(response.data as Map<String, dynamic>);
    } on FunctionException catch (e) {
      throw SystemHealthException(
        (e.details is Map && (e.details as Map)['error'] != null)
            ? (e.details as Map)['error'].toString()
            : 'Could not check integration status.',
      );
    }
  }

  Future<List<RateLimitSummaryRow>> fetchRateLimitSummary() async {
    try {
      final rows = await _client.rpc('get_rate_limit_summary') as List;
      return rows
          .map(
            (row) =>
                RateLimitSummaryRow.fromMap(row as Map<String, dynamic>),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw SystemHealthException(e.message);
    }
  }

  Future<RoadDistanceCacheStats> fetchRoadDistanceCacheStats() async {
    try {
      final rows =
          await _client.rpc('get_road_distance_cache_stats') as List;
      if (rows.isEmpty) return RoadDistanceCacheStats.empty;
      return RoadDistanceCacheStats.fromMap(
        rows.first as Map<String, dynamic>,
      );
    } on PostgrestException catch (e) {
      throw SystemHealthException(e.message);
    }
  }
}
