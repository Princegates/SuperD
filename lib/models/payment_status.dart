import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum PaymentStatus {
  pending,
  paid,
  failed,
  refunded;

  static PaymentStatus fromString(String value) {
    return switch (value) {
      'pending' => PaymentStatus.pending,
      'paid' => PaymentStatus.paid,
      'failed' => PaymentStatus.failed,
      'refunded' => PaymentStatus.refunded,
      _ => PaymentStatus.pending,
    };
  }

  String get wireValue => switch (this) {
    PaymentStatus.pending => 'pending',
    PaymentStatus.paid => 'paid',
    PaymentStatus.failed => 'failed',
    PaymentStatus.refunded => 'refunded',
  };

  String get label => switch (this) {
    PaymentStatus.pending => 'Payment pending',
    PaymentStatus.paid => 'Paid',
    PaymentStatus.failed => 'Payment failed',
    PaymentStatus.refunded => 'Refunded',
  };

  Color get color => switch (this) {
    PaymentStatus.pending => AppTheme.warning,
    PaymentStatus.paid => AppTheme.success,
    PaymentStatus.failed => AppTheme.danger,
    PaymentStatus.refunded => AppTheme.neutral,
  };
}
