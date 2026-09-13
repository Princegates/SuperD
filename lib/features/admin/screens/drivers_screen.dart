import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/delivery_rating.dart';
import '../../../models/driver_vehicle_type.dart';
import '../../../models/profile.dart';
import '../../../models/staff_permission.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';
import '../widgets/person_card.dart';

/// The driver roster, split out of [TeamScreen] into its own section so
/// driver-specific settings (freeze, vehicle grouping, and anything added
/// later - e.g. a daily-fee tier pin, see Console > Daily Fees) have a
/// dedicated home instead of being buried in the general staff list. Open
/// to a dispatcher as well as a super admin - managing the driver roster
/// is routine dispatch work, same reasoning as opening up Commission/Daily
/// Fees confirmation.
class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Profile driver,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove driver?'),
        content: Text(
          "This deletes ${driver.displayName}'s account. They won't be able "
          'to sign in anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(profileRepositoryProvider).deleteStaffAccount(driver.id);
      unawaited(
        logAuditEvent(
          ref.read(supabaseClientProvider),
          action: 'staff_removed',
          entityType: 'profile',
          entityId: driver.id,
          summary: 'Removed driver ${driver.displayName}',
        ),
      );
      ref
        ..invalidate(allProfilesProvider)
        ..invalidate(driversListProvider);
    } on StaffManagementException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove this driver')),
        );
      }
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Profile driver,
  ) async {
    final newActive = !driver.isActive;
    try {
      await ref.read(profileRepositoryProvider).setActive(driver.id, newActive);
      unawaited(
        logAuditEvent(
          ref.read(supabaseClientProvider),
          action: newActive ? 'driver_approved' : 'staff_deactivated',
          entityType: 'profile',
          entityId: driver.id,
          summary:
              '${newActive ? 'Approved' : 'Deactivated'} '
              'driver ${driver.displayName}',
        ),
      );
      ref
        ..invalidate(allProfilesProvider)
        ..invalidate(driversListProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this driver')),
        );
      }
    }
  }

  /// Super-admin only (enforced server-side too - see
  /// `enforce_profile_role_change()`). Freezing blocks a driver from
  /// accepting or being assigned new work (e.g. unpaid commission) without
  /// signing them out or touching anything already in progress.
  Future<void> _toggleFrozen(
    BuildContext context,
    WidgetRef ref,
    Profile driver,
  ) async {
    final freeze = !driver.isFrozen;
    if (freeze) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Freeze ${driver.displayName}?'),
          content: const Text(
            "They'll keep access to deliveries already assigned to them, "
            "but won't be able to accept a new one or be assigned another "
            'until unfrozen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Freeze'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref.read(profileRepositoryProvider).setFrozen(driver.id, freeze);
      unawaited(
        logAuditEvent(
          ref.read(supabaseClientProvider),
          action: freeze ? 'driver_frozen' : 'driver_unfrozen',
          entityType: 'profile',
          entityId: driver.id,
          summary:
              '${freeze ? 'Froze' : 'Unfroze'} driver ${driver.displayName}',
        ),
      );
      ref
        ..invalidate(allProfilesProvider)
        ..invalidate(driversListProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this driver')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProfile = ref.watch(currentProfileProvider).valueOrNull;
    final isSuperAdmin = myProfile?.role == UserRole.superAdmin;
    final canManageDrivers =
        myProfile?.hasPermission(StaffPermission.manageDrivers) ?? false;
    final driversAsync = ref.watch(driversListProvider);
    final ratings =
        ref.watch(driverRatingSummaryProvider).valueOrNull ?? const {};
    final poorRatings = ref.watch(poorRatingsProvider).valueOrNull ?? const [];
    final deliveries = ref.watch(allDeliveriesProvider).valueOrNull ?? const [];
    final work = _WorkStats.byDriver(deliveries);

    return Scaffold(
      floatingActionButton: canManageDrivers
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.push('/admin/team/new', extra: UserRole.driver),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add driver'),
            )
          : null,
      body: AsyncValueView<List<Profile>>(
        value: driversAsync,
        data: (drivers) {
          if (drivers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No drivers yet. Tap "Add driver" below, or ask them to '
                  'create an account from the app themselves.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          const order = [
            DriverVehicleType.motorbike,
            DriverVehicleType.car,
            DriverVehicleType.vanTruck,
            DriverVehicleType.tricycle,
          ];
          final byType = <DriverVehicleType?, List<Profile>>{};
          for (final driver in drivers) {
            byType.putIfAbsent(driver.vehicleType, () => []).add(driver);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (poorRatings.isNotEmpty)
                _PoorRatings(ratings: poorRatings, drivers: drivers),
              for (final type in [...order, null])
                if (byType[type] case final group? when group.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Text(
                      type?.label ?? 'Unspecified vehicle',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  for (final driver in group)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PersonCard(
                        person: driver,
                        rating: ratings[driver.id],
                        workline: work[driver.id]?.summary,
                        isMe: driver.id == myProfile?.id,
                        isSuperAdmin: isSuperAdmin,
                        canManageDriver: canManageDrivers,
                        onToggleActive: () =>
                            _toggleActive(context, ref, driver),
                        onToggleFrozen: () =>
                            _toggleFrozen(context, ref, driver),
                        onEdit: () =>
                            context.push('/admin/team/edit', extra: driver),
                        onDelete: () => _confirmDelete(context, ref, driver),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Recent ratings of three or below, above the roster.
///
/// Customers have been leaving these since 0034 and no screen has ever
/// shown them. They sit here rather than in a tab of their own because
/// the answer to a bad rating is almost always a conversation with the
/// driver, whose row is directly underneath.
class _PoorRatings extends StatelessWidget {
  const _PoorRatings({required this.ratings, required this.drivers});

  final List<DeliveryRating> ratings;
  final List<Profile> drivers;

  String _driverName(String id) {
    for (final driver in drivers) {
      if (driver.id == id) return driver.displayName;
    }
    return 'Unknown driver';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppTheme.danger.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sentiment_dissatisfied_outlined,
                  size: 18,
                  color: AppTheme.danger,
                ),
                const SizedBox(width: 8),
                Text(
                  ratings.length == 1
                      ? '1 poor rating'
                      : '${ratings.length} poor ratings',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final rating in ratings.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${'\u2605' * rating.rating}'
                      '${'\u2606' * (5 - rating.rating)}'
                      '  ${_driverName(rating.driverId)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // The comment is the whole point; a bare score says
                    // someone was unhappy but never why.
                    if (rating.comment case final comment?)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '\u201c$comment\u201d',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (ratings.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'and ${ratings.length - 5} more',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a rider's delivery record says about them, beyond how customers
/// scored them.
///
/// A rating tells you whether someone was pleasant. This tells you
/// whether they finish: how many they have completed, how long they
/// typically take from collection to hand-over, and how often they gave
/// a job back. All of it comes from timestamps the deliveries already
/// carry, so it costs no extra query.
class _WorkStats {
  _WorkStats();

  int completed = 0;
  int handedBack = 0;
  final List<Duration> _legs = [];

  void _add(Duration leg) => _legs.add(leg);

  /// The typical trip, taken as the median rather than the mean - one
  /// rider who forgot to close a delivery until the next morning should
  /// not make the whole roster look slow.
  Duration? get typicalLeg {
    if (_legs.isEmpty) return null;
    final sorted = [..._legs]..sort();
    return sorted[sorted.length ~/ 2];
  }

  String get summary {
    final parts = <String>['$completed done'];
    if (typicalLeg case final leg?) {
      final minutes = leg.inMinutes;
      parts.add(
        minutes >= 60
            ? '~${(minutes / 60).toStringAsFixed(1)}h a trip'
            : '~$minutes min a trip',
      );
    }
    if (handedBack > 0) {
      parts.add('$handedBack handed back');
    }
    return parts.join(' \u00b7 ');
  }

  static Map<String, _WorkStats> byDriver(List<Delivery> deliveries) {
    final out = <String, _WorkStats>{};
    for (final delivery in deliveries) {
      final driverId = delivery.assignedDriverId;
      if (driverId == null) continue;
      final stats = out.putIfAbsent(driverId, _WorkStats.new);

      if (delivery.status == DeliveryStatus.delivered) {
        stats.completed++;
        // Collection to hand-over is the part the rider controls. Time
        // from when the order was raised includes however long dispatch
        // took to assign it, which is not theirs to answer for.
        if (delivery.pickedUpAt case final from?) {
          if (delivery.deliveredAt case final to?) {
            if (to.isAfter(from)) stats._add(to.difference(from));
          }
        }
      } else if (delivery.status == DeliveryStatus.cancelled) {
        stats.handedBack++;
      }
    }
    return out;
  }
}
