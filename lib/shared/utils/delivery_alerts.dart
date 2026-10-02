import '../../models/delivery.dart';
import '../../models/delivery_status.dart';

/// How long a delivery may sit in a status before it's worth someone
/// looking at it. Only the states where nothing happens without a
/// person: a delivered or cancelled job is finished, and a scheduled one
/// not yet due is handled separately (see [dueSoon]/[overdue]).
///
/// Promoted out of `AdminDashboardScreen._stuck()` so the Deliveries
/// board banner and the Console Dashboard's unified alerts feed
/// (`alerts_providers.dart`) share one threshold table instead of two
/// that could quietly drift apart.
const stuckAfter = {
  DeliveryStatus.pending: Duration(minutes: 20),
  DeliveryStatus.assigned: Duration(minutes: 45),
  DeliveryStatus.pickedUp: Duration(hours: 3),
  DeliveryStatus.inTransit: Duration(hours: 3),
};

/// Deliveries that have been sitting too long in a status that should
/// have moved on. A scheduled delivery whose time has not come yet is
/// not stuck - it is waiting on purpose.
List<Delivery> stuckDeliveries(List<Delivery> all, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final overdue = <Delivery>[];
  for (final delivery in all) {
    final limit = stuckAfter[delivery.status];
    if (limit == null) continue;
    if (delivery.scheduledAt case final at? when at.isAfter(n)) continue;
    // Measured from the last thing that actually happened to it, so a
    // job assigned two minutes ago is not judged on when it was raised.
    final since =
        delivery.pickedUpAt ?? delivery.assignedAt ?? delivery.createdAt;
    if (n.difference(since) > limit) overdue.add(delivery);
  }
  overdue.sort((a, b) {
    final aSince = a.pickedUpAt ?? a.assignedAt ?? a.createdAt;
    final bSince = b.pickedUpAt ?? b.assignedAt ?? b.createdAt;
    return aSince.compareTo(bSince);
  });
  return overdue;
}

/// The window [ScheduledDeliveryBanner] treats as "coming up soon" -
/// shared with the unified alerts feed so the two agree on what counts.
const dueSoonThreshold = Duration(minutes: 30);

List<Delivery> dueSoonDeliveries(List<Delivery> all, {DateTime? now}) {
  return all
      .where((d) => d.isDueSoon(dueSoonThreshold, now: now))
      .toList();
}

List<Delivery> overdueScheduledDeliveries(
  List<Delivery> all, {
  DateTime? now,
}) {
  return all.where((d) => d.isOverdue(now: now)).toList();
}
