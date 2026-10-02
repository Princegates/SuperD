import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/system_health.dart';
import '../../../shared/widgets/async_value_view.dart';
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
          _Card(
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
          const SizedBox(height: 16),
          _Card(
            title: 'Public form traffic',
            subtitle: 'Rate-limited request volume by action',
            icon: Icons.shield_outlined,
            iconColor: AppTheme.accent,
            child: AsyncValueView<List<RateLimitSummaryRow>>(
              value: rateLimitState,
              data: (rows) => rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No rate-limited requests in the last 24h',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : Column(
                      children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(child: Text(row.action)),
                                Text(
                                  '${row.hitsLastHour} / hr · '
                                  '${row.hitsLast24h} / 24h',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
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
          const SizedBox(height: 16),
          _Card(
            title: 'Road-distance cache',
            subtitle: 'How well cached routes are avoiding a fresh Google call',
            icon: Icons.route_outlined,
            iconColor: AppTheme.success,
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
    final color = configured ? AppTheme.success : AppTheme.neutral;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (!configured)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      impact,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            configured ? 'Configured' : 'Not set',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
