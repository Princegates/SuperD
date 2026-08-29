import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../models/driver_vehicle_type.dart';
import '../../../models/profile.dart';
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
            child: const Text('Remove', style: TextStyle(color: AppTheme.danger)),
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
          summary: '${newActive ? 'Approved' : 'Deactivated'} '
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
    final driversAsync = ref.watch(driversListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('/admin/team/new', extra: UserRole.driver),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add driver'),
      ),
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
                        isMe: driver.id == myProfile?.id,
                        isSuperAdmin: isSuperAdmin,
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
