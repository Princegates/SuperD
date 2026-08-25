import 'package:flutter/material.dart';

enum PaymentMethod {
  cash,
  card,
  mobileMoney,
  bankTransfer,
  other;

  static PaymentMethod fromString(String value) {
    return switch (value) {
      'cash' => PaymentMethod.cash,
      'card' => PaymentMethod.card,
      'mobile_money' => PaymentMethod.mobileMoney,
      'bank_transfer' => PaymentMethod.bankTransfer,
      _ => PaymentMethod.other,
    };
  }

  String get wireValue => switch (this) {
    PaymentMethod.cash => 'cash',
    PaymentMethod.card => 'card',
    PaymentMethod.mobileMoney => 'mobile_money',
    PaymentMethod.bankTransfer => 'bank_transfer',
    PaymentMethod.other => 'other',
  };

  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.card => 'Card',
    PaymentMethod.mobileMoney => 'Mobile money',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.other => 'Other',
  };

  IconData get icon => switch (this) {
    PaymentMethod.cash => Icons.payments_outlined,
    PaymentMethod.card => Icons.credit_card_outlined,
    PaymentMethod.mobileMoney => Icons.phone_iphone_outlined,
    PaymentMethod.bankTransfer => Icons.account_balance_outlined,
    PaymentMethod.other => Icons.more_horiz,
  };
}
