import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/driver_notice.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/console_providers.dart';

/// The display name of whichever driver in [drivers] has this [id], or
/// null if there's no match (e.g. the driver was since deleted).
String? _driverNameById(List<Profile> drivers, String? id) {
  if (id == null) return null;
  for (final driver in drivers) {
    if (driver.id == id) return driver.displayName;
  }
  return null;
}

/// Lets a dispatcher/super admin post a notice to drivers - a broadcast
/// (every driver sees it, e.g. a promotion) or a direct message to one
/// specific driver - and review/end ones already posted. See
/// `driver_notices` in `0046_driver_notices.sql`.
class ConsoleNoticesTab extends ConsumerStatefulWidget {
  const ConsoleNoticesTab({super.key});

  @override
  ConsumerState<ConsoleNoticesTab> createState() => _ConsoleNoticesTabState();
}

class _ConsoleNoticesTabState extends ConsumerState<ConsoleNoticesTab> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String? _targetDriverId;
  DateTime? _expiresAt;
  bool _isPosting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both a title and a message.')),
      );
      return;
    }

    setState(() => _isPosting = true);
    try {
      await ref
          .read(driverNoticeRepositoryProvider)
          .create(
            title: title,
            body: body,
            targetDriverId: _targetDriverId,
            expiresAt: _expiresAt,
          );
      final driverName = _driverNameById(
        ref.read(driversListProvider).valueOrNull ?? [],
        _targetDriverId,
      );
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'driver_notice_posted',
        entityType: 'driver_notice',
        summary: _targetDriverId == null
            ? 'Posted a notice to all drivers: "$title"'
            : 'Sent a message to ${driverName ?? 'a driver'}: "$title"',
      );
      ref.invalidate(allDriverNoticesProvider);
      if (mounted) {
        _titleController.clear();
        _bodyController.clear();
        setState(() {
          _targetDriverId = null;
          _expiresAt = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Notice posted.')));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deactivate(DriverNotice notice) async {
    await ref.read(driverNoticeRepositoryProvider).deactivate(notice.id);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'driver_notice_ended',
      entityType: 'driver_notice',
      summary: 'Ended the notice "${notice.title}" early',
    );
    ref.invalidate(allDriverNoticesProvider);
  }

  Future<void> _delete(DriverNotice notice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this notice?'),
        content: Text(
          'This permanently removes "${notice.title}" - it will no longer '
          'show for anyone, and this can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(driverNoticeRepositoryProvider).delete(notice.id);
    ref.invalidate(allDriverNoticesProvider);
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final noticesState = ref.watch(allDriverNoticesProvider);
    final expiresAt = _expiresAt;
    final expiryLabel = expiresAt == null
        ? "Doesn't expire on its own"
        : 'Expires ${DateFormat('d MMM yyyy').format(expiresAt)}';
    // Posting/ending/deleting a notice stays open to a plain dispatcher
    // (unchanged) - only an auditor is blocked, per
    // `0054_auditor_role_permissions.sql`. Note this is deliberately NOT
    // "isSuperAdmin", unlike the other admin-only tabs - Notices isn't one
    // of them (see admin_shell_screen.dart), a dispatcher reaches this
    // screen too and must keep full access.
    final canWrite =
        ref.watch(currentProfileProvider).valueOrNull?.role !=
        UserRole.auditor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!canWrite)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.neutral.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                      color: AppTheme.neutral,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "You can see what's been sent but can't post, end, "
                        'or delete a notice - ask a dispatcher or super '
                        'admin.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (canWrite)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Post a notice',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send every driver a promotion or heads-up, or pick '
                      'one driver to message directly. Shows as a '
                      "dismissible banner on the driver's own dashboard.",
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyController,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: _targetDriverId,
                      decoration: const InputDecoration(
                        labelText: 'Send to',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All drivers (broadcast)'),
                        ),
                        for (final driver in drivers)
                          DropdownMenuItem<String?>(
                            value: driver.id,
                            child: Text(driver.displayName),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _targetDriverId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            expiryLabel,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                        TextButton(
                          onPressed: _pickExpiry,
                          child: Text(
                            _expiresAt == null ? 'Set expiry' : 'Change',
                          ),
                        ),
                        if (_expiresAt != null)
                          IconButton(
                            onPressed: () =>
                                setState(() => _expiresAt = null),
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear expiry',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isPosting ? null : _post,
                        child: _isPosting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _targetDriverId == null
                                    ? 'Post to all drivers'
                                    : 'Send message',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Sent notices',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 10),
          AsyncValueView<List<DriverNotice>>(
            value: noticesState,
            data: (notices) {
              if (notices.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No notices posted yet.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                );
              }
              return Column(
                children: [
                  for (final notice in notices)
                    _NoticeRow(
                      notice: notice,
                      driverName: _driverNameById(
                        drivers,
                        notice.targetDriverId,
                      ),
                      onDeactivate: canWrite ? () => _deactivate(notice) : null,
                      onDelete: canWrite ? () => _delete(notice) : null,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.notice,
    required this.driverName,
    required this.onDeactivate,
    required this.onDelete,
  });

  final DriverNotice notice;
  final String? driverName;

  /// Null hides the action row entirely - for a viewer who can see notices
  /// but can't write to them (an auditor - see
  /// `0054_auditor_role_permissions.sql`).
  final VoidCallback? onDeactivate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isLive = notice.isActive && !notice.isExpired;
    final when = DateFormat('d MMM, h:mm a').format(notice.createdAt.toLocal());
    final who = notice.targetDriverId == null
        ? 'All drivers'
        : 'To ${driverName ?? 'a driver'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    notice.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (isLive ? AppTheme.success : Colors.grey).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isLive
                        ? 'Active'
                        : (notice.isExpired ? 'Expired' : 'Ended'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isLive ? AppTheme.success : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(notice.body),
            const SizedBox(height: 6),
            Text(
              '$who · $when',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            if (onDeactivate != null || onDelete != null) ...[
              if (isLive) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onDeactivate,
                      child: const Text('End now'),
                    ),
                    TextButton(
                      onPressed: onDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ] else
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
