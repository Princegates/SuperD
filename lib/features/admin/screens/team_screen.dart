import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

/// Dispatchers see the driver roster and can add/edit/delete drivers. Super
/// admins see everyone and can also change roles right here instead of
/// needing SQL.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

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
      await ref.read(profileRepositoryProvider).deleteDriver(driver.id);
      ref
        ..invalidate(allProfilesProvider)
        ..invalidate(driversListProvider);
    } on DriverManagementException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove this driver')),
        );
      }
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
      appBar: AppBar(title: Text(isSuperAdmin ? 'Team' : 'Drivers')),
      floatingActionButton: FloatingActionButton.extended(
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
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final person = items[index];
              final isMe = person.id == myProfile?.id;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      person.displayName.isNotEmpty
                          ? person.displayName[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  title: Text(person.displayName),
                  subtitle: Text(
                    person.phone?.isNotEmpty == true
                        ? '${person.email} · ${person.phone}'
                        : person.email,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (person.role == UserRole.driver) ...[
                        IconButton(
                          tooltip: 'Edit driver',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => context.push(
                            '/admin/team/edit',
                            extra: person,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove driver',
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppTheme.danger,
                          ),
                          onPressed: () =>
                              _confirmDelete(context, ref, person),
                        ),
                      ],
                      if (isSuperAdmin)
                        _RoleControl(person: person, enabled: !isMe),
                    ],
                  ),
                ),
              );
            },
          );
        },
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
            .then((_) => ref.invalidate(allProfilesProvider));
      },
      itemBuilder: (context) => [
        for (final role in UserRole.values)
          PopupMenuItem(value: role, child: Text(role.label)),
      ],
      child: chip,
    );
  }
}
