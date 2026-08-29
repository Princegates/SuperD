import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/driver_notice.dart';

/// One card per notice currently visible to the signed-in driver -
/// broadcasts (promotions, platform-wide heads-up) and their own direct
/// messages alike, newest first. Each is dismissible on its own; closing
/// one only affects this driver (see `dismiss_driver_notice()`), so a
/// broadcast promotion stays visible to everyone else who hasn't closed
/// it yet.
class DriverNoticeList extends ConsumerWidget {
  const DriverNoticeList({super.key, required this.notices});

  final List<DriverNotice> notices;

  Future<void> _dismiss(WidgetRef ref, String noticeId) async {
    await ref.read(driverNoticeRepositoryProvider).dismiss(noticeId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (notices.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final notice in notices)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: notice.isBroadcast
                  ? AppTheme.accent.withValues(alpha: 0.1)
                  : AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: notice.isBroadcast
                    ? AppTheme.accent.withValues(alpha: 0.3)
                    : AppTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  notice.isBroadcast
                      ? Icons.campaign_outlined
                      : Icons.mark_email_unread_outlined,
                  size: 20,
                  color: notice.isBroadcast
                      ? AppTheme.accent
                      : AppTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notice.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        notice.body,
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _dismiss(ref, notice.id),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 18),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
