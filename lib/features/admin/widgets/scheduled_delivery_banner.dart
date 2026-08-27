import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../shared/utils/scheduled_delivery.dart';

/// An animated, dismissible-free banner listing scheduled deliveries that
/// are due soon (or overdue) and still haven't gone out - a pulsing nudge
/// that these need a driver now, not whenever the list happens to be
/// scrolled past. Recomputes against a fresh `DateTime.now()` on every
/// build, so the parent just needs to rebuild this periodically (see the
/// `Timer.periodic` in [AdminDashboardScreen]) for it to stay accurate as
/// time passes, independent of any actual data change.
class ScheduledDeliveryBanner extends StatefulWidget {
  const ScheduledDeliveryBanner({super.key, required this.deliveries});

  final List<Delivery> deliveries;

  @override
  State<ScheduledDeliveryBanner> createState() =>
      _ScheduledDeliveryBannerState();
}

class _ScheduledDeliveryBannerState extends State<ScheduledDeliveryBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  bool _expanded = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final due =
        widget.deliveries
            .where(
              (d) =>
                  d.isDueSoon(scheduledDueSoonThreshold, now: now) ||
                  d.isOverdue(now: now),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));

    if (due.isEmpty) return const SizedBox.shrink();

    final anyOverdue = due.any((d) => d.isOverdue(now: now));
    final color = anyOverdue ? AppTheme.danger : AppTheme.warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) => Transform.scale(
                      scale: 1 + (_pulse.value * 0.25),
                      child: child,
                    ),
                    child: Icon(Icons.alarm, color: color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      anyOverdue
                          ? '${due.length} scheduled '
                                '${due.length == 1 ? 'delivery is' : 'deliveries are'} '
                                'overdue for dispatch'
                          : '${due.length} scheduled '
                                '${due.length == 1 ? 'delivery needs' : 'deliveries need'} '
                                'a driver soon',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  for (final delivery in due)
                    _ScheduledRow(
                      delivery: delivery,
                      color: delivery.isOverdue(now: now)
                          ? AppTheme.danger
                          : AppTheme.warning,
                    ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({required this.delivery, required this.color});

  final Delivery delivery;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('h:mm a').format(delivery.scheduledAt!);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/admin/delivery/${delivery.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(
              timeLabel,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '#${delivery.trackingCode} · ${delivery.customerName}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}
