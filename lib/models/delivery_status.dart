import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum DeliveryStatus {
  pending,
  assigned,
  pickedUp,
  inTransit,
  delivered,
  cancelled;

  static DeliveryStatus fromString(String value) {
    return switch (value) {
      'pending' => DeliveryStatus.pending,
      'assigned' => DeliveryStatus.assigned,
      'picked_up' => DeliveryStatus.pickedUp,
      'in_transit' => DeliveryStatus.inTransit,
      'delivered' => DeliveryStatus.delivered,
      'cancelled' => DeliveryStatus.cancelled,
      _ => DeliveryStatus.pending,
    };
  }

  /// The value stored in Postgres (matches the `delivery_status` enum).
  String get wireValue => switch (this) {
    DeliveryStatus.pending => 'pending',
    DeliveryStatus.assigned => 'assigned',
    DeliveryStatus.pickedUp => 'picked_up',
    DeliveryStatus.inTransit => 'in_transit',
    DeliveryStatus.delivered => 'delivered',
    DeliveryStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    DeliveryStatus.pending => 'Pending',
    DeliveryStatus.assigned => 'Assigned',
    DeliveryStatus.pickedUp => 'Picked up',
    DeliveryStatus.inTransit => 'In transit',
    DeliveryStatus.delivered => 'Delivered',
    DeliveryStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    DeliveryStatus.pending => AppTheme.neutral,
    DeliveryStatus.assigned => AppTheme.warning,
    DeliveryStatus.pickedUp => AppTheme.primary,
    DeliveryStatus.inTransit => AppTheme.primary,
    DeliveryStatus.delivered => AppTheme.success,
    DeliveryStatus.cancelled => AppTheme.danger,
  };

  IconData get icon => switch (this) {
    DeliveryStatus.pending => Icons.hourglass_empty,
    DeliveryStatus.assigned => Icons.person_pin_circle_outlined,
    DeliveryStatus.pickedUp => Icons.inventory_2_outlined,
    DeliveryStatus.inTransit => Icons.local_shipping_outlined,
    DeliveryStatus.delivered => Icons.check_circle_outline,
    DeliveryStatus.cancelled => Icons.cancel_outlined,
  };

  /// What a driver is allowed to move this status to next, in order.
  DeliveryStatus? get nextForDriver => switch (this) {
    DeliveryStatus.assigned => DeliveryStatus.pickedUp,
    DeliveryStatus.pickedUp => DeliveryStatus.inTransit,
    DeliveryStatus.inTransit => DeliveryStatus.delivered,
    _ => null,
  };
}
