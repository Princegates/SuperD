import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/system_health.dart';

/// Whether each optional third-party integration is configured - the raw
/// data behind Console > System Health's Integrations section. Resolves
/// with an error for anyone but a super admin (enforced server-side in
/// the `admin-integration-status` Edge Function, not just by hiding the
/// tab) - `AsyncValueView` shows that as a normal error state.
final integrationStatusProvider = FutureProvider<IntegrationStatus>((ref) {
  return ref.watch(systemHealthRepositoryProvider).fetchIntegrationStatus();
});

final rateLimitSummaryProvider = FutureProvider<List<RateLimitSummaryRow>>((
  ref,
) {
  return ref.watch(systemHealthRepositoryProvider).fetchRateLimitSummary();
});

final roadDistanceCacheStatsProvider = FutureProvider<RoadDistanceCacheStats>((
  ref,
) {
  return ref
      .watch(systemHealthRepositoryProvider)
      .fetchRoadDistanceCacheStats();
});
