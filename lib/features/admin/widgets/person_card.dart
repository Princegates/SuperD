import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../providers/admin_providers.dart';

/// One person's row on the Team or Drivers screen - shared between the two
/// since both list a [Profile] with the same activate/freeze/edit/delete
/// actions and (for a super admin) the same role control.
class PersonCard extends StatelessWidget {
  const PersonCard({
    super.key,
    required this.person,
    required this.isMe,
    required this.isSuperAdmin,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
    this.onToggleFrozen,
  });

  final Profile person;
  final bool isMe;
  final bool isSuperAdmin;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Null hides the freeze control entirely - only ever passed for a
  /// driver row (freezing a dispatcher/super admin isn't a thing).
  final VoidCallback? onToggleFrozen;

  @override
  Widget build(BuildContext context) {
    // A super admin's own row (or any other super admin's, for that
    // matter) isn't a roster edit through these icons - removing/editing
    // one that way isn't wired up; the role control below is the one
    // action available on this row, and only if it isn't your own.
    final canManage = person.role != UserRole.superAdmin;
    final canFreeze = isSuperAdmin && onToggleFrozen != null;

    // A ListTile's title/subtitle only get whatever width is left after
    // `leading` and `trailing` - cramming every action into `trailing`
    // (up to 5 icon buttons plus a role dropdown) could squeeze that down
    // to almost nothing on a narrow phone, and Flutter's Text falls back
    // to wrapping one character per line rather than overflowing. A plain
    // Column sidesteps this: the name/contact row gets an Expanded (a
    // real, bounded width) on its own line, and actions get their own
    // full-width row underneath that can Wrap onto a second line instead
    // of stealing space from the text above it.
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Text(
                    person.displayName.isNotEmpty
                        ? person.displayName[0].toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            person.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (!person.isActive)
                            PersonStatusBadge(
                              label: 'Pending approval',
                              color: AppTheme.warning,
                            ),
                          if (person.isFrozen)
                            PersonStatusBadge(
                              label: 'Frozen',
                              color: AppTheme.danger,
                            ),
                          // Only drivers have an online/offline concept -
                          // it's their own "available for new deliveries"
                          // toggle (see DriverDashboardScreen), meaningless
                          // for a dispatcher/super admin's own profile.
                          if (person.role == UserRole.driver)
                            PersonStatusBadge(
                              label: person.isOnline ? 'Online' : 'Offline',
                              color: person.isOnline
                                  ? AppTheme.success
                                  : Colors.grey.shade500,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        person.phone?.isNotEmpty == true
                            ? '${person.email} · ${person.phone}'
                            : person.email,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canManage) ...[
                  IconButton(
                    tooltip: person.isActive
                        ? 'Deactivate ${person.role.label.toLowerCase()}'
                        : 'Approve ${person.role.label.toLowerCase()}',
                    icon: Icon(
                      person.isActive
                          ? Icons.toggle_on
                          : Icons.toggle_off_outlined,
                      size: 26,
                      color: person.isActive
                          ? AppTheme.success
                          : Colors.black38,
                    ),
                    onPressed: onToggleActive,
                  ),
                  if (canFreeze)
                    IconButton(
                      tooltip: person.isFrozen
                          ? 'Unfreeze driver'
                          : 'Freeze driver (e.g. unpaid commission)',
                      icon: Icon(
                        person.isFrozen
                            ? Icons.ac_unit
                            : Icons.ac_unit_outlined,
                        size: 20,
                        color: person.isFrozen
                            ? AppTheme.danger
                            : Colors.black38,
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
                if (isSuperAdmin) RoleControl(person: person, enabled: !isMe),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PersonStatusBadge extends StatelessWidget {
  const PersonStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

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

/// A super admin's role-change dropdown for one person - disabled ([enabled]
/// false) for their own row, since you can't demote yourself here.
class RoleControl extends ConsumerWidget {
  const RoleControl({super.key, required this.person, required this.enabled});

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
              ref
                ..invalidate(allProfilesProvider)
                ..invalidate(driversListProvider);
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
