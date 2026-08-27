import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum CommissionStatus {
  due,
  paid,
  waived;

  static CommissionStatus fromString(String value) {
    return switch (value) {
      'due' => CommissionStatus.due,
      'paid' => CommissionStatus.paid,
      'waived' => CommissionStatus.waived,
      _ => CommissionStatus.due,
    };
  }

  String get wireValue => switch (this) {
    CommissionStatus.due => 'due',
    CommissionStatus.paid => 'paid',
    CommissionStatus.waived => 'waived',
  };

  String get label => switch (this) {
    CommissionStatus.due => 'Due',
    CommissionStatus.paid => 'Paid',
    CommissionStatus.waived => 'Waived',
  };

  Color get color => switch (this) {
    CommissionStatus.due => AppTheme.warning,
    CommissionStatus.paid => AppTheme.success,
    CommissionStatus.waived => AppTheme.neutral,
  };
}
