import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/user_role.dart';
import '../../admin/providers/admin_providers.dart';

/// A single place to see who was recently onboarded - staff and vendors -
/// and what's still incomplete about their setup, with a direct link into
/// the existing Team/Vendors edit screens to fix it. This doesn't
/// duplicate those screens' forms; it's a triage view on top of them.
class ConsoleOnboardingTab extends ConsumerWidget {
  const ConsoleOnboardingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(allProfilesProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];

    final staff = profiles.where((p) => p.role != UserRole.superAdmin).toList()
      ..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Staff',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        if (staff.isEmpty)
          const _EmptyCard(text: 'No staff added yet')
        else
          for (final person in staff.take(10))
            _OnboardingCard(
              title: person.displayName,
              subtitle: '${person.role.label} · ${person.email}',
              badges: [
                if (person.mustChangePassword)
                  const _Badge(
                    text: 'Awaiting password setup',
                    color: AppTheme.warning,
                  ),
              ],
              createdAt: person.createdAt,
              onTap: () => context.push('/admin/team/edit', extra: person),
            ),
        const SizedBox(height: 24),
        Text(
          'Vendors',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        if (vendors.isEmpty)
          const _EmptyCard(text: 'No vendors registered yet')
        else
          for (final vendor in vendors.take(10))
            _OnboardingCard(
              title: vendor.vendorName,
              subtitle: vendor.phone,
              badges: [
                if (!vendor.isActive)
                  const _Badge(text: 'Inactive', color: AppTheme.danger),
                if (vendor.zoneId == null)
                  const _Badge(text: 'No zone', color: AppTheme.neutral),
              ],
              createdAt: vendor.createdAt,
              onTap: () => context.push('/admin/vendors/edit', extra: vendor),
            ),
      ],
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.title,
    required this.subtitle,
    required this.badges,
    required this.createdAt,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<_Badge> badges;
  final DateTime? createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (createdAt != null)
              Text(
                DateFormat('dd MMM yyyy').format(createdAt!.toLocal()),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: badges),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: Colors.grey.shade500)),
      ),
    );
  }
}
