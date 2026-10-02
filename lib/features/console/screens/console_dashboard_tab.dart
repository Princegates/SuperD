import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/console_design.dart';
import '../../../models/audit_log_entry.dart';
import '../../../models/commission_payment.dart';
import '../../../models/commission_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/system_alert.dart';
import '../../../shared/widgets/alert_row.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/console/console_card.dart';
import '../../../shared/widgets/tile_grid.dart';
import '../../../shared/widgets/trend_chart.dart';
import '../../../shared/widgets/trend_stat_tile.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/alerts_providers.dart';
import '../providers/console_providers.dart';

/// The Console's rich landing tab for a super admin/auditor - real trends
/// (not just all-time totals, which is all `ConsoleOverviewTab` could
/// show), a unified "needs attention" feed, and a glance at recent system
/// activity. Replaces Overview in that slot; a plain dispatcher still
/// gets `HomeScreen` instead (see `AdminShellScreen`) - several of the
/// providers this reads are empty for that role by RLS design, and a
/// dashboard full of zeroes would read as broken, not as "nothing to see
/// here".
class ConsoleDashboardTab extends ConsumerWidget {
  const ConsoleDashboardTab({super.key, required this.onNavigate});

  /// Jumps to a Console section by its nav label (e.g. "Drivers",
  /// "Daily Fees") - same callback `AdminShellScreen` already hands
  /// `HomeScreen`, passed through here for [SystemAlert.sectionLabel]
  /// taps.
  final void Function(String label) onNavigate;

  static const _trendDays = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(deliveryHistoryProvider);
    final recent = ref.watch(recentDeliveriesProvider).valueOrNull ?? [];
    final commission = ref.watch(allCommissionPaymentsProvider).valueOrNull ?? [];
    final alerts = ref.watch(systemAlertsProvider);
    final activityState = ref.watch(auditLogProvider);

    return AsyncValueView<List<Delivery>>(
      value: historyState,
      data: (allDeliveries) {
        final now = DateTime.now();
        final weekAgo = now.subtract(const Duration(days: 7));
        final twoWeeksAgo = now.subtract(const Duration(days: 14));

        final thisWeek = allDeliveries
            .where((d) => d.createdAt.isAfter(weekAgo))
            .length;
        final priorWeek = allDeliveries
            .where(
              (d) =>
                  d.createdAt.isAfter(twoWeeksAgo) &&
                  !d.createdAt.isAfter(weekAgo),
            )
            .length;
        final weekChange = priorWeek == 0
            ? null
            : (thisWeek - priorWeek) / priorWeek;

        final active = recent
            .where(
              (d) => const {
                DeliveryStatus.pending,
                DeliveryStatus.assigned,
                DeliveryStatus.pickedUp,
                DeliveryStatus.inTransit,
              }.contains(d.status),
            )
            .length;

        final delivered = allDeliveries
            .where((d) => d.status == DeliveryStatus.delivered)
            .length;
        final completionRate = allDeliveries.isEmpty
            ? 0.0
            : delivered / allDeliveries.length;

        final dueCommissionCurrency = _dominantCurrency(commission);
        final dueCommission = commission
            .where(
              (c) =>
                  c.status == CommissionStatus.due &&
                  c.currency == dueCommissionCurrency,
            )
            .fold(0.0, (s, c) => s + c.amount);

        final deliveryTrend = _dailyCounts(
          allDeliveries.map((d) => d.createdAt).toList(),
          days: _trendDays,
        );
        final commissionTrend = _dailySums(
          commission
              .where((c) => c.currency == dueCommissionCurrency)
              .toList(),
          days: _trendDays,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TileGrid(
              children: [
                TrendStatTile(
                  label: 'Deliveries this week',
                  value: '$thisWeek',
                  color: AppTheme.primary,
                  changeFraction: weekChange,
                ),
                TrendStatTile(
                  label: 'Active right now',
                  value: '$active',
                  color: AppTheme.accent,
                ),
                TrendStatTile(
                  label: 'Completion rate (all time)',
                  value: '${(completionRate * 100).toStringAsFixed(0)}%',
                  color: AppTheme.success,
                ),
                TrendStatTile(
                  label: dueCommissionCurrency == null
                      ? 'Commission due'
                      : 'Commission due ($dueCommissionCurrency)',
                  value: dueCommission.toStringAsFixed(2),
                  color: AppTheme.warning,
                  increaseIsGood: false,
                ),
              ],
            ),
            const SizedBox(height: 22),
            ConsoleCard(
              title: 'Delivery volume',
              subtitle: 'Last $_trendDays days',
              icon: Icons.local_shipping_outlined,
              iconColor: AppTheme.primary,
              child: TrendChart(
                points: deliveryTrend,
                color: AppTheme.primary,
                labelEvery: 2,
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              title: 'Commission due',
              subtitle: dueCommissionCurrency == null
                  ? 'Last $_trendDays days'
                  : 'Last $_trendDays days · $dueCommissionCurrency',
              icon: Icons.request_quote_outlined,
              iconColor: AppTheme.accent,
              child: TrendChart(
                points: commissionTrend,
                color: AppTheme.accent,
                labelEvery: 2,
                valueFormatter: (v) => v.toStringAsFixed(0),
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              title: 'Needs attention',
              subtitle: alerts.isEmpty ? 'All clear' : '${alerts.length} item(s)',
              icon: Icons.notifications_active_outlined,
              iconColor: alerts.any(
                    (a) => a.severity == SystemAlertSeverity.danger,
                  )
                  ? AppTheme.danger
                  : AppTheme.warning,
              child: alerts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Nothing needs attention right now',
                        style: TextStyle(color: ConsoleColors.inkMuted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final alert in alerts.take(8))
                          AlertRow(
                            alert: alert,
                            onTap: alert.route != null
                                ? () => context.push(alert.route!)
                                : alert.sectionLabel != null
                                ? () => onNavigate(alert.sectionLabel!)
                                : null,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              title: 'Recent activity',
              icon: Icons.history,
              iconColor: AppTheme.neutral,
              trailing: TextButton(
                onPressed: () => onNavigate('Audit log'),
                child: const Text('View all'),
              ),
              child: activityState.when(
                data: (entries) => entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No activity recorded yet',
                          style: TextStyle(color: ConsoleColors.inkMuted),
                        ),
                      )
                    : Column(
                        children: [
                          for (final entry in entries.take(8))
                            _ActivityRow(entry: entry),
                        ],
                      ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, _) => Text(
                  "Couldn't load recent activity",
                  style: TextStyle(color: ConsoleColors.inkMuted),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The currency with the most commission rows, or null if there are
  /// none yet - picking one rather than summing across currencies, which
  /// would add amounts that don't share a unit.
  static String? _dominantCurrency(List<CommissionPayment> commission) {
    if (commission.isEmpty) return null;
    final counts = <String, int>{};
    for (final c in commission) {
      counts.update(c.currency, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<TrendPoint> _dailyCounts(
    List<DateTime> timestamps, {
    required int days,
  }) {
    final now = DateTime.now();
    final counts = <DateTime, int>{};
    for (final t in timestamps) {
      final day = DateTime(t.year, t.month, t.day);
      counts.update(day, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = DateTime(now.year, now.month, now.day - i);
          return TrendPoint(DateFormat('d MMM').format(day), (counts[day] ?? 0).toDouble());
        }(),
    ];
  }

  static List<TrendPoint> _dailySums(
    List<CommissionPayment> rows, {
    required int days,
  }) {
    final now = DateTime.now();
    final sums = <DateTime, double>{};
    for (final c in rows) {
      final day = DateTime(c.createdAt.year, c.createdAt.month, c.createdAt.day);
      sums.update(day, (s) => s + c.amount, ifAbsent: () => c.amount);
    }
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = DateTime(now.year, now.month, now.day - i);
          return TrendPoint(DateFormat('d MMM').format(day), sums[day] ?? 0);
        }(),
    ];
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.summary, style: const TextStyle(fontSize: 13)),
                if (entry.actorName != null)
                  Text(
                    entry.actorName!,
                    style: TextStyle(
                      color: ConsoleColors.inkMuted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('d MMM, h:mm a').format(entry.createdAt.toLocal()),
            style: TextStyle(fontSize: 11, color: ConsoleColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
