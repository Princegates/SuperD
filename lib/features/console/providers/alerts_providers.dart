import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/delivery_status.dart';
import '../../../models/system_alert.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/delivery_alerts.dart';
import '../../admin/providers/admin_providers.dart';

/// The Console Dashboard's unified "needs attention" feed - every signal
/// that used to be a scattered banner, a private per-screen helper, or a
/// toast that vanished the instant it was dismissed, folded into one
/// list every role-appropriate screen can read.
///
/// A plain derived [Provider], not a Future/Stream one, matching
/// `rankedDriversProvider`'s shape: it combines `.valueOrNull` off
/// providers that are already being fetched/watched elsewhere, so it
/// inherits their loading/realtime/error behavior for free rather than
/// re-querying anything itself.
///
/// "New delivery"/"unassigned" are deliberately NOT edge-triggered here
/// (unlike the one-time snackbars `AdminShellScreen` still shows - this
/// complements those, it doesn't replace them): a dashboard panel that's
/// supposed to stay accurate across reloads needs a steady-state
/// condition, not a diff against whatever was last seen, so "needs a
/// driver" is simply every delivery currently sitting at `pending` -
/// true the moment it's created, true again if a driver rejects it, and
/// true for as long as it stays that way, with no separate "seen it
/// already" tracking required.
final systemAlertsProvider = Provider<List<SystemAlert>>((ref) {
  final deliveries = ref.watch(recentDeliveriesProvider).valueOrNull ?? [];
  final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
  final unpaidIds = ref.watch(unpaidDriverIdsTodayProvider).valueOrNull ?? {};
  final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];

  final alerts = <SystemAlert>[];

  for (final d in stuckDeliveries(deliveries)) {
    alerts.add(
      SystemAlert(
        id: 'stuck-${d.id}',
        severity: SystemAlertSeverity.danger,
        icon: Icons.schedule_outlined,
        title: 'Delivery #${d.trackingCode} has stalled',
        subtitle: 'Still ${d.status.label.toLowerCase()} longer than usual',
        createdAt: d.pickedUpAt ?? d.assignedAt ?? d.createdAt,
        route: '/admin/delivery/${d.id}',
      ),
    );
  }

  // Every currently-pending delivery needs a driver, whether it's brand
  // new or was bounced back by a reject/cancel - stuckDeliveries() above
  // already covers one that's been pending past the stuck threshold, so
  // this only adds the ones still within it (no duplicate alert for the
  // same delivery).
  final stuckIds = {for (final d in stuckDeliveries(deliveries)) d.id};
  for (final d in deliveries) {
    if (d.status != DeliveryStatus.pending) continue;
    if (stuckIds.contains(d.id)) continue;
    alerts.add(
      SystemAlert(
        id: 'needs-driver-${d.id}',
        severity: SystemAlertSeverity.warning,
        icon: Icons.person_search_outlined,
        title: 'Delivery #${d.trackingCode} needs a driver',
        subtitle: d.customerName,
        createdAt: d.createdAt,
        route: '/admin/delivery/${d.id}',
      ),
    );
  }

  for (final d in overdueScheduledDeliveries(deliveries)) {
    alerts.add(
      SystemAlert(
        id: 'overdue-scheduled-${d.id}',
        severity: SystemAlertSeverity.danger,
        icon: Icons.event_busy_outlined,
        title: 'Delivery #${d.trackingCode} missed its scheduled time',
        subtitle: d.customerName,
        createdAt: d.scheduledAt ?? d.createdAt,
        route: '/admin/delivery/${d.id}',
      ),
    );
  }

  for (final d in dueSoonDeliveries(deliveries)) {
    alerts.add(
      SystemAlert(
        id: 'due-soon-${d.id}',
        severity: SystemAlertSeverity.warning,
        icon: Icons.alarm_outlined,
        title: 'Delivery #${d.trackingCode} is due soon',
        subtitle: d.customerName,
        createdAt: d.scheduledAt ?? d.createdAt,
        route: '/admin/delivery/${d.id}',
      ),
    );
  }

  final frozenCount = drivers.where((d) => d.isFrozen).length;
  if (frozenCount > 0) {
    alerts.add(
      SystemAlert(
        id: 'frozen-drivers',
        severity: SystemAlertSeverity.danger,
        icon: Icons.ac_unit_outlined,
        title: '$frozenCount ${frozenCount == 1 ? 'driver' : 'drivers'} '
            'frozen',
        subtitle: "Can't be assigned work until unfrozen",
        createdAt: DateTime.now(),
        sectionLabel: 'Drivers',
      ),
    );
  }

  if (unpaidIds.isNotEmpty) {
    alerts.add(
      SystemAlert(
        id: 'unpaid-daily-fee',
        severity: SystemAlertSeverity.warning,
        icon: Icons.payments_outlined,
        title: "${unpaidIds.length} ${unpaidIds.length == 1 ? 'driver' : 'drivers'} "
            "owe today's fee",
        subtitle: 'Blocked from new assignments until settled',
        createdAt: DateTime.now(),
        sectionLabel: 'Daily Fees',
      ),
    );
  }

  final recentVendorCutoff = DateTime.now().subtract(const Duration(hours: 24));
  for (final Vendor v in vendors) {
    if (v.createdAt.isBefore(recentVendorCutoff)) continue;
    alerts.add(
      SystemAlert(
        id: 'new-vendor-${v.id}',
        severity: SystemAlertSeverity.neutral,
        icon: Icons.storefront_outlined,
        title: 'New vendor: ${v.vendorName}',
        subtitle: v.isActive ? 'Active' : 'Awaiting activation',
        createdAt: v.createdAt,
        sectionLabel: 'Vendors',
      ),
    );
  }

  alerts.sort((a, b) {
    // Danger, then warning, then neutral; newest first within each.
    final severityOrder = SystemAlertSeverity.values.indexOf(a.severity)
        .compareTo(SystemAlertSeverity.values.indexOf(b.severity));
    if (severityOrder != 0) return severityOrder;
    return b.createdAt.compareTo(a.createdAt);
  });
  return alerts;
});
