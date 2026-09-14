import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/core_providers.dart';

enum _AccountAction { profile, changePassword, signOut }

/// Overflow menu with account actions (change password, sign out), shown in
/// the AppBar of both the dispatcher and driver dashboards.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({
    super.key,
    required this.changePasswordRoute,
    this.profileRoute,
  });

  final String changePasswordRoute;

  /// Where "My profile" goes, when this account has one worth showing.
  /// Null on the dispatcher dashboard, which has no such screen - the menu
  /// simply leaves the entry out rather than offering a dead end.
  final String? profileRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (action) {
        switch (action) {
          case _AccountAction.profile:
            if (profileRoute != null) context.push(profileRoute!);
          case _AccountAction.changePassword:
            context.push(changePasswordRoute);
          case _AccountAction.signOut:
            ref.read(authRepositoryProvider).signOut();
        }
      },
      itemBuilder: (context) => [
        if (profileRoute != null)
          const PopupMenuItem(
            value: _AccountAction.profile,
            child: ListTile(
              leading: Icon(Icons.badge_outlined),
              title: Text('My profile'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: _AccountAction.changePassword,
          child: ListTile(
            leading: Icon(Icons.lock_reset_outlined),
            title: Text('Change password'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
