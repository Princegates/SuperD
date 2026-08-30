import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum DeliveryStatus {
  pending,
  assigned,
  inTransit,
  pickedUp,
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
    DeliveryStatus.inTransit => 'In transit',
    DeliveryStatus.pickedUp => 'Picked up',
    DeliveryStatus.delivered => 'Delivered',
    DeliveryStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    DeliveryStatus.pending => AppTheme.neutral,
    DeliveryStatus.assigned => AppTheme.warning,
    DeliveryStatus.inTransit => AppTheme.primary,
    DeliveryStatus.pickedUp => AppTheme.primary,
    DeliveryStatus.delivered => AppTheme.success,
    DeliveryStatus.cancelled => AppTheme.danger,
  };

  IconData get icon => switch (this) {
    DeliveryStatus.pending => Icons.hourglass_empty,
    DeliveryStatus.assigned => Icons.person_pin_circle_outlined,
    DeliveryStatus.inTransit => Icons.local_shipping_outlined,
    DeliveryStatus.pickedUp => Icons.inventory_2_outlined,
    DeliveryStatus.delivered => Icons.check_circle_outline,
    DeliveryStatus.cancelled => Icons.cancel_outlined,
  };

  /// The driver-facing job flow, in order: a dispatcher assigns the
  /// delivery, the driver accepts it and begins the trip to pickup
  /// ("in transit"), collects the package on arrival ("picked up"), then
  /// delivers it.
  DeliveryStatus? get nextForDriver => switch (this) {
    DeliveryStatus.assigned => DeliveryStatus.inTransit,
    DeliveryStatus.inTransit => DeliveryStatus.pickedUp,
    DeliveryStatus.pickedUp => DeliveryStatus.delivered,
    _ => null,
  };

  /// The reverse of [nextForDriver] - lets a driver undo a status they
  /// tapped by mistake, one step at a time. `assigned` has no previous step
  /// here on purpose: backing out of an assignment entirely is "reject",
  /// not "undo" - see `driver_reject_delivery` in
  /// `0023_driver_reject_and_undo.sql`. `delivered` has none either, also
  /// on purpose - the customer has already handed over the PIN to confirm
  /// receipt at that point (see `complete_delivery_with_pin` in
  /// `0056_delivery_completion_pin.sql`), so there's nothing left to
  /// "undo by mistake"; enforced server-side too, see
  /// `enforce_delivery_update()`.
  DeliveryStatus? get previousForDriver => switch (this) {
    DeliveryStatus.inTransit => DeliveryStatus.assigned,
    DeliveryStatus.pickedUp => DeliveryStatus.inTransit,
    _ => null,
  };
}
