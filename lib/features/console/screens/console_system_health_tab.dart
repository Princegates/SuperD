import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/console_design.dart';
import '../../../models/system_health.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/console/console_badge.dart';
import '../../../shared/widgets/console/console_card.dart';
import '../providers/system_health_providers.dart';

/// Super-admin-only: whether each optional third-party integration is
/// configured, plus aggregate stats on the two operational tables
/// (`rate_limit_hits`, `road_distance_cache`) that have existed since
/// early on but never had any admin visibility. Entirely read-only - a
/// credential is never edited here, only whether one is present; the
/// actual secret stays in Supabase's own Edge Function secrets, never
/// reaching this screen or the client at all. See
/// `admin-integration-status` and `0099_rate_limit_and_cache_admin_stats.sql`.
class ConsoleSystemHealthTab extends ConsumerWidget {
  const ConsoleSystemHealthTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final integrationState = ref.watch(integrationStatusProvider);
    final rateLimitState = ref.watch(rateLimitSummaryProvider);
    final cacheState = ref.watch(roadDistanceCacheStatsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(integrationStatusProvider);
        ref.invalidate(rateLimitSummaryProvider);
        ref.invalidate(roadDistanceCacheStatsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConsoleCard(
            title: 'Integrations',
            subtitle:
                'Whether each optional service is configured - never the '
                'credential itself',
            icon: Icons.cable_outlined,
            iconColor: AppTheme.primary,
            child: AsyncValueView<IntegrationStatus>(
              value: integrationState,
              data: (status) => Column(
                children: [
                  for (final (label, configured, impact) in status.rows)
                    _IntegrationRow(
                      label: label,
                      configured: configured,
                      impact: impact,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: ConsoleSpace.lg),
          ConsoleCard(
            title: 'Public form traffic',
            subtitle: 'Rate-limited request volume by action',
            icon: Icons.shield_outlined,
            iconColor: AppTheme.accent,
            child: AsyncValueView<List<RateLimitSummaryRow>>(
              value: rateLimitState,
              data: (rows) => rows.isEmpty
                  ? const ConsoleEmptyState(
                      'No rate-limited requests in the last 24h',
                    )
                  : Column(
                      children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(row.action, style: ConsoleText.body),
                                ),
                                Text(
                                  '${row.hitsLastHour} / hr · '
                                  '${row.hitsLast24h} / 24h',
                                  style: ConsoleText.number.copyWith(
                                    fontSize: 12.5,
                                    color: ConsoleColors.inkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: ConsoleSpace.lg),
          ConsoleCard(
            title: 'Road-distance cache',
            subtitle: 'How well cached routes are avoiding a fresh Google call',
            icon: Icons.route_outlined,
            iconColor: ConsoleColors.success,
            child: AsyncValueView<RoadDistanceCacheStats>(
              value: cacheState,
              data: (stats) => Row(
                children: [
                  _MiniStat(
                    label: 'Cached routes',
                    value: NumberFormat.decimalPattern().format(
                      stats.totalRoutes,
                    ),
                  ),
                  _MiniStat(
                    label: 'Added, last 24h',
                    value: NumberFormat.decimalPattern().format(
                      stats.routesAddedLast24h,
                    ),
                  ),
                  _MiniStat(
                    label: 'Avg. reuse',
                    value: '${stats.avgHitsPerRoute.toStringAsFixed(1)}x',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrationRow extends StatelessWidget {
  const _IntegrationRow({
    required this.label,
    required this.configured,
    required this.impact,
  });

  final String label;
  final bool configured;
  final String impact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ConsoleText.body.copyWith(fontWeight: FontWeight.w700)),
                if (!configured)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(impact, style: ConsoleText.bodyMuted),
                  ),
              ],
            ),
          ),
          ConsoleBadge(
            label: configured ? 'Configured' : 'Not set',
            color: configured ? ConsoleColors.success : ConsoleColors.inkFaint,
            icon: configured ? Icons.check_circle : Icons.remove_circle_outline,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: ConsoleText.statValue.copyWith(
              fontSize: 20,
              color: ConsoleColors.success,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: ConsoleText.eyebrow),
        ],
      ),
    );
  }
}
