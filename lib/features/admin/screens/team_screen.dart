import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

/// Dispatchers see a read-only driver directory. Super admins see everyone
/// and can change roles right here instead of needing SQL.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProfile = ref.watch(currentProfileProvider).valueOrNull;
    final isSuperAdmin = myProfile?.role == UserRole.superAdmin;

    final peopleAsync = isSuperAdmin
        ? ref.watch(allProfilesProvider)
        : ref.watch(driversListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isSuperAdmin ? 'Team' : 'Drivers')),
      body: AsyncValueView<List<Profile>>(
        value: peopleAsync,
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No drivers yet. Ask them to create an account from the app '
                  '– they will appear here automatically.',
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
                  trailing: isSuperAdmin
                      ? _RoleControl(person: person, enabled: !isMe)
                      : null,
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
