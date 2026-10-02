import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/admin/providers/admin_providers.dart';

/// "Live"/"Reconnecting" chip for the Console `AppBar`, next to
/// [AccountMenuButton] - visible on every section, every role, since a
/// dropped realtime connection matters just as much on Live Map or
/// Deliveries as on the Dashboard. Reads [connectionStatusProvider].
class ConnectionStatusDot extends ConsumerWidget {
  const ConnectionStatusDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectionStatusProvider);
    final color = connected ? AppTheme.success : AppTheme.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: connected
            ? 'Live - realtime updates connected'
            : 'Reconnecting - realtime updates may be delayed',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? 'Live' : 'Reconnecting',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
