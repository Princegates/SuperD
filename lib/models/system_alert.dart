import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum SystemAlertSeverity { danger, warning, neutral }

extension SystemAlertSeverityColor on SystemAlertSeverity {
  Color get color => switch (this) {
    SystemAlertSeverity.danger => AppTheme.danger,
    SystemAlertSeverity.warning => AppTheme.warning,
    SystemAlertSeverity.neutral => AppTheme.neutral,
  };
}

/// One row of the Console Dashboard's unified "needs attention" feed -
/// everything that used to be a scattered banner, a private per-screen
/// helper, or a snackbar that vanished the moment it was dismissed
/// (see `alerts_providers.dart`), now one shape every source folds into.
///
/// [sectionLabel] jumps to that Console section by name (matches
/// `AdminShellScreen`'s `goToLabel`); [route] pushes a specific detail
/// screen (e.g. a delivery) instead. At most one is set - a neither-set
/// alert is informational only, with no tap action.
class SystemAlert {
  const SystemAlert({
    required this.id,
    required this.severity,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.sectionLabel,
    this.route,
  });

  /// Stable across rebuilds for the same underlying thing (a delivery id,
  /// a driver id, ...) so the feed doesn't reorder/flicker every time its
  /// source providers re-emit.
  final String id;

  final SystemAlertSeverity severity;
  final IconData icon;
  final String title;
  final String subtitle;

  /// What this alert is "about" happening/starting, for sorting the feed
  /// newest-first - not necessarily when the alert itself was computed.
  final DateTime createdAt;

  final String? sectionLabel;
  final String? route;
}
