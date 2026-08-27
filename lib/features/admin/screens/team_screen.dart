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

/// The "Team" section of the admin dashboard shell ([AdminShellScreen]).
/// Dispatchers see the driver roster and can add/edit/delete drivers. Super
/// admins see everyone, can also add/edit/delete dispatchers, and can
/// change anyone's role right here instead of needing SQL.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Profile person,
  ) async {
    final roleLabel = person.role.label.toLowerCase();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $roleLabel?'),
        content: Text(
          "This deletes ${person.displayName}'s account. They won't be able "
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
      await ref.read(profileRepositoryProvider).deleteStaffAccount(person.id);
      unawaited(
        logAuditEvent(
          ref.read(supabaseClientProvider),
          action: 'staff_removed',
          entityType: 'profile',
          entityId: person.id,
          summary: 'Removed $roleLabel ${person.displayName}',
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
          SnackBar(content: Text('Could not remove this $roleLabel')),
        );
      }
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Profile person,
  ) async {
    final newActive = !person.isActive;
    try {
      await ref.read(profileRepositoryProvider).setActive(person.id, newActive);
      unawaited(
        logAuditEvent(
          ref.read(supabaseClientProvider),
          action: newActive ? 'driver_approved' : 'staff_deactivated',
          entityType: 'profile',
          entityId: person.id,
          summary:
              '${newActive ? 'Approved' : 'Deactivated'} '
              '${person.role.label.toLowerCase()} ${person.displayName}',
        ),
      );
      ref
        ..invalidate(allProfilesProvider)
        ..invalidate(driversListProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this account')),
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

  Future<void> _showAddMenu(BuildContext context) async {
    final role = await showModalBottomSheet<UserRole>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Add driver'),
              onTap: () => Navigator.of(context).pop(UserRole.driver),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Add dispatcher'),
              onTap: () => Navigator.of(context).pop(UserRole.dispatcher),
            ),
          ],
        ),
      ),
    );
    if (role != null && context.mounted) {
      context.push('/admin/team/new', extra: role);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProfile = ref.watch(currentProfileProvider).valueOrNull;
    final isSuperAdmin = myProfile?.role == UserRole.superAdmin;

    final peopleAsync = isSuperAdmin
        ? ref.watch(allProfilesProvider)
        : ref.watch(driversListProvider);

    return Scaffold(
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddMenu(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add'),
            )
          : FloatingActionButton.extended(
              onPressed: () => context.push('/admin/team/new'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add driver'),
            ),
      body: AsyncValueView<List<Profile>>(
        value: peopleAsync,
        data: (items) {
          if (items.isEmpty) {
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
          final rows = _groupedRows(items: items, isSuperAdmin: isSuperAdmin);
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return switch (row) {
                _HeaderRow() => Padding(
                  padding: EdgeInsets.fromLTRB(4, index == 0 ? 0 : 16, 4, 8),
                  child: Text(
                    row.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: row.isSubHeader ? 12.5 : 14,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _PersonRow() => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PersonCard(
                    person: row.person,
                    isMe: row.person.id == myProfile?.id,
                    isSuperAdmin: isSuperAdmin,
                    onToggleActive: () =>
                        _toggleActive(context, ref, row.person),
                    onToggleFrozen: () =>
                        _toggleFrozen(context, ref, row.person),
                    onEdit: () =>
                        context.push('/admin/team/edit', extra: row.person),
                    onDelete: () => _confirmDelete(context, ref, row.person),
                  ),
                ),
              };
            },
          );
        },
      ),
    );
  }

  /// Drivers grouped separately from other staff, and sub-grouped by
  /// vehicle type within that - dispatchers only ever see the driver
  /// roster in the first place, so for them this is just the vehicle-type
  /// grouping with no top-level "Drivers" header needed.
  List<_Row> _groupedRows({
    required List<Profile> items,
    required bool isSuperAdmin,
  }) {
    final rows = <_Row>[];

    void addVehicleGroups(List<Profile> drivers) {
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
      for (final type in [...order, null]) {
        final group = byType[type];
        if (group == null || group.isEmpty) continue;
        rows.add(
          _HeaderRow(type?.label ?? 'Unspecified vehicle', isSubHeader: true),
        );
        rows.addAll(group.map(_PersonRow.new));
      }
    }

    if (isSuperAdmin) {
      final drivers = items.where((p) => p.role == UserRole.driver).toList();
      final dispatchers = items
          .where((p) => p.role == UserRole.dispatcher)
          .toList();
      final admins = items.where((p) => p.role == UserRole.superAdmin).toList();

      if (drivers.isNotEmpty) {
        rows.add(_HeaderRow('Drivers (${drivers.length})'));
        addVehicleGroups(drivers);
      }
      if (dispatchers.isNotEmpty) {
        rows.add(_HeaderRow('Dispatchers (${dispatchers.length})'));
        rows.addAll(dispatchers.map(_PersonRow.new));
      }
      if (admins.isNotEmpty) {
        rows.add(_HeaderRow('Super Admins (${admins.length})'));
        rows.addAll(admins.map(_PersonRow.new));
      }
    } else {
      addVehicleGroups(items);
    }

    return rows;
  }
}

sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.title, {this.isSubHeader = false});
  final String title;
  final bool isSubHeader;
}

class _PersonRow extends _Row {
  _PersonRow(this.person);
  final Profile person;
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.isMe,
    required this.isSuperAdmin,
    required this.onToggleActive,
    required this.onToggleFrozen,
    required this.onEdit,
    required this.onDelete,
  });

  final Profile person;
  final bool isMe;
  final bool isSuperAdmin;
  final VoidCallback onToggleActive;
  final VoidCallback onToggleFrozen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canManage = person.role != UserRole.superAdmin;
    final canFreeze = isSuperAdmin && person.role == UserRole.driver;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            person.displayName.isNotEmpty
                ? person.displayName[0].toUpperCase()
                : '?',
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(person.displayName)),
            if (!person.isActive) ...[
              const SizedBox(width: 8),
              _Badge(label: 'Pending approval', color: AppTheme.warning),
            ],
            if (person.isFrozen) ...[
              const SizedBox(width: 8),
              _Badge(label: 'Frozen', color: AppTheme.danger),
            ],
          ],
        ),
        subtitle: Text(
          person.phone?.isNotEmpty == true
              ? '${person.email} · ${person.phone}'
              : person.email,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage) ...[
              IconButton(
                tooltip: person.isActive
                    ? 'Deactivate ${person.role.label.toLowerCase()}'
                    : 'Approve ${person.role.label.toLowerCase()}',
                icon: Icon(
                  person.isActive ? Icons.toggle_on : Icons.toggle_off_outlined,
                  size: 26,
                  color: person.isActive ? AppTheme.success : Colors.black38,
                ),
                onPressed: onToggleActive,
              ),
              if (canFreeze)
                IconButton(
                  tooltip: person.isFrozen
                      ? 'Unfreeze driver'
                      : 'Freeze driver (e.g. unpaid commission)',
                  icon: Icon(
                    person.isFrozen ? Icons.ac_unit : Icons.ac_unit_outlined,
                    size: 20,
                    color: person.isFrozen ? AppTheme.danger : Colors.black38,
                  ),
                  onPressed: onToggleFrozen,
                ),
              IconButton(
                tooltip: 'Edit ${person.role.label.toLowerCase()}',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Remove ${person.role.label.toLowerCase()}',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppTheme.danger,
                ),
                onPressed: onDelete,
              ),
            ],
            if (isSuperAdmin) _RoleControl(person: person, enabled: !isMe),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _RoleControl extends ConsumerWidget {
  const _RoleControl({required this.person, required this.enabled});

  final Profile person;
  final bool enabled;

  Color _colorFor(UserRole role) => switch (role) {
    UserRole.driver => AppTheme.neutral,
    UserRole.dispatcher => AppTheme.primary,
    UserRole.superAdmin => AppTheme.accent,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _colorFor(person.role);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            person.role.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ],
      ),
    );

    if (!enabled) return chip;

    return PopupMenuButton<UserRole>(
      tooltip: 'Change role',
      initialValue: person.role,
      onSelected: (role) {
        if (role == person.role) return;
        ref
            .read(profileRepositoryProvider)
            .updateRole(userId: person.id, role: role)
            .then((_) {
              unawaited(
                logAuditEvent(
                  ref.read(supabaseClientProvider),
                  action: 'role_changed',
                  entityType: 'profile',
                  entityId: person.id,
                  summary:
                      "Changed ${person.displayName}'s role to ${role.label}",
                ),
              );
              ref.invalidate(allProfilesProvider);
            });
      },
      itemBuilder: (context) => [
        for (final role in UserRole.values)
          PopupMenuItem(value: role, child: Text(role.label)),
      ],
      child: chip,
    );
  }
}
