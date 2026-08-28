import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum DailyFeeStatus {
  pending,
  paid,
  failed,
  waived;

  static DailyFeeStatus fromString(String value) {
    return switch (value) {
      'pending' => DailyFeeStatus.pending,
      'paid' => DailyFeeStatus.paid,
      'failed' => DailyFeeStatus.failed,
      'waived' => DailyFeeStatus.waived,
      _ => DailyFeeStatus.pending,
    };
  }

  String get wireValue => switch (this) {
    DailyFeeStatus.pending => 'pending',
    DailyFeeStatus.paid => 'paid',
    DailyFeeStatus.failed => 'failed',
    DailyFeeStatus.waived => 'waived',
  };

  String get label => switch (this) {
    DailyFeeStatus.pending => 'Pending',
    DailyFeeStatus.paid => 'Paid',
    DailyFeeStatus.failed => 'Failed',
    DailyFeeStatus.waived => 'Waived',
  };

  Color get color => switch (this) {
    DailyFeeStatus.pending => AppTheme.warning,
    DailyFeeStatus.paid => AppTheme.success,
    DailyFeeStatus.failed => AppTheme.danger,
    DailyFeeStatus.waived => AppTheme.neutral,
  };
}
