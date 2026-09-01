import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';
import '../widgets/person_card.dart';

/// The "Team" section of the admin dashboard shell ([AdminShellScreen]) -
/// staff only (dispatchers and super admins). Super-admin-only in the nav:
/// dispatcher management is exclusive to a super admin (see the README),
/// so a dispatcher has nothing to do here. The driver roster lives in its
/// own [DriversScreen] instead, open to both roles - see the split's
/// rationale there.
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
      ref.invalidate(allProfilesProvider);
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
      ref.invalidate(allProfilesProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this account')),
        );
      }
    }
  }

  Future<void> _pickRoleAndAdd(BuildContext context) async {
    final role = await showModalBottomSheet<UserRole>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Add dispatcher'),
              subtitle: const Text('Runs day-to-day dispatch operations'),
              onTap: () => Navigator.of(context).pop(UserRole.dispatcher),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Add auditor'),
              subtitle: const Text(
                'Same dispatch access as a dispatcher; read-only on the '
                'admin-only Console tabs',
              ),
              onTap: () => Navigator.of(context).pop(UserRole.auditor),
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
    final peopleAsync = ref.watch(allProfilesProvider);

    return Scaffold(
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _pickRoleAndAdd(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add team member'),
            )
          : null,
      body: AsyncValueView<List<Profile>>(
        value: peopleAsync,
        data: (items) {
          final dispatchers = items
              .where((p) => p.role == UserRole.dispatcher)
              .toList();
          final admins = items
              .where((p) => p.role == UserRole.superAdmin)
              .toList();
          final auditors = items
              .where((p) => p.role == UserRole.auditor)
              .toList();

          if (dispatchers.isEmpty && admins.isEmpty && auditors.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isSuperAdmin
                      ? 'No other staff yet. Tap "Add team member" below.'
                      : 'No other staff yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (dispatchers.isNotEmpty) ...[
                _SectionHeader('Dispatchers (${dispatchers.length})'),
                for (final person in dispatchers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PersonCard(
                      person: person,
                      isMe: person.id == myProfile?.id,
                      isSuperAdmin: isSuperAdmin,
                      onToggleActive: () => _toggleActive(context, ref, person),
                      onEdit: () =>
                          context.push('/admin/team/edit', extra: person),
                      onDelete: () => _confirmDelete(context, ref, person),
                    ),
                  ),
              ],
              if (admins.isNotEmpty) ...[
                _SectionHeader('Super Admins (${admins.length})'),
                for (final person in admins)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PersonCard(
                      person: person,
                      isMe: person.id == myProfile?.id,
                      isSuperAdmin: isSuperAdmin,
                      onToggleActive: () => _toggleActive(context, ref, person),
                      onEdit: () =>
                          context.push('/admin/team/edit', extra: person),
                      onDelete: () => _confirmDelete(context, ref, person),
                    ),
                  ),
              ],
              if (auditors.isNotEmpty) ...[
                _SectionHeader('Auditors (${auditors.length})'),
                for (final person in auditors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PersonCard(
                      person: person,
                      isMe: person.id == myProfile?.id,
                      isSuperAdmin: isSuperAdmin,
                      onToggleActive: () => _toggleActive(context, ref, person),
                      onEdit: () =>
                          context.push('/admin/team/edit', extra: person),
                      onDelete: () => _confirmDelete(context, ref, person),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
