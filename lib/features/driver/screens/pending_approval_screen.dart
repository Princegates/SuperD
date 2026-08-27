import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Shown instead of the driver dashboard while a self-signed-up driver is
/// waiting on a dispatcher or super admin to approve them (see the
/// router's redirect and `rankedDriversProvider`, which keeps a pending
/// driver out of the assignment picker too). A driver an admin created
/// directly is never routed here - that account starts already approved.
class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 64,
                  color: AppTheme.warning,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Account pending approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  "You're all signed up, but a dispatcher or admin still "
                  'needs to approve your account before you can start '
                  "receiving deliveries. We'll let you know once that's "
                  'done - try signing in again later.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
