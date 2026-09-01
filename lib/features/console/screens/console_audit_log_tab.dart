import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/audit_log_entry.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/console_providers.dart';

/// Who did what, and when - every entry here was written by
/// `log_audit_event` right after the action it describes actually
/// succeeded, so this is a record of what happened, not what was
/// attempted.
class ConsoleAuditLogTab extends ConsumerWidget {
  const ConsoleAuditLogTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logState = ref.watch(auditLogProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(auditLogProvider),
      child: AsyncValueView<List<AuditLogEntry>>(
        value: logState,
        data: (entries) {
          if (entries.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: 400,
                  child: Center(
                    child: Text(
                      'No activity recorded yet',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _LogRow(entry: entries[index]),
          );
        },
      ),
    );
  }
}

({IconData icon, Color color}) _iconFor(String action) {
  if (action == 'user_signed_in') {
    return (icon: Icons.login, color: Colors.teal.shade400);
  }
  if (action == 'user_signed_out') {
    return (icon: Icons.logout, color: Colors.blueGrey.shade400);
  }
  if (action == 'user_signed_up') {
    return (
      icon: Icons.person_add_alt_1_outlined,
      color: Colors.green.shade600,
    );
  }
  if (action.contains('deactivat') || action == 'staff_removed') {
    return (icon: Icons.remove_circle_outline, color: Colors.red.shade400);
  }
  if (action.contains('created') ||
      action.contains('registered') ||
      action.contains('activated')) {
    return (icon: Icons.add_circle_outline, color: Colors.green.shade600);
  }
  if (action.contains('role')) {
    return (icon: Icons.swap_horiz, color: Colors.deepPurple.shade300);
  }
  if (action.contains('payment')) {
    return (icon: Icons.payments_outlined, color: Colors.amber.shade700);
  }
  if (action.contains('driver_assigned')) {
    return (icon: Icons.local_shipping_outlined, color: Colors.blue.shade400);
  }
  if (action == 'password_reset') {
    return (icon: Icons.lock_reset_outlined, color: Colors.orange.shade600);
  }
  return (icon: Icons.edit_outlined, color: Colors.blueGrey);
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final style = _iconFor(entry.action);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: style.color.withValues(alpha: 0.12),
              child: Icon(style.icon, size: 17, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.summary,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${entry.actorName ?? 'Someone'} · '
                    '${DateFormat('dd MMM, h:mm a').format(entry.createdAt.toLocal())}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
