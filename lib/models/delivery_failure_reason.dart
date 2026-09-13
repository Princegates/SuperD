import 'package:flutter/material.dart';

/// Why a rider went out and the parcel did not change hands.
///
/// The delivery's [DeliveryStatus] stays `cancelled` when this is set -
/// see `0089_failed_delivery_outcome.sql` for why the status enum was
/// deliberately left alone. This is the column that separates "the rider
/// went and it did not work out" from "a dispatcher called it off before
/// anyone rode", which until now were the same row.
///
/// The list is short on purpose. A rider taps one of these on the road,
/// one-handed, often in a hurry; six options they can tell apart at a
/// glance produce data worth counting, and twenty do not. Anything that
/// does not fit is [other] plus a note in their own words.
enum DeliveryFailureReason {
  customerAbsent,
  customerRefused,
  wrongAddress,
  unreachable,
  packageIssue,
  other;

  /// Null for anything unrecognised, so a value added to the Postgres
  /// enum ahead of an app release degrades to "no reason shown" rather
  /// than crashing a rider's screen mid-shift.
  static DeliveryFailureReason? fromString(String? value) {
    return switch (value) {
      'customer_absent' => DeliveryFailureReason.customerAbsent,
      'customer_refused' => DeliveryFailureReason.customerRefused,
      'wrong_address' => DeliveryFailureReason.wrongAddress,
      'unreachable' => DeliveryFailureReason.unreachable,
      'package_issue' => DeliveryFailureReason.packageIssue,
      'other' => DeliveryFailureReason.other,
      _ => null,
    };
  }

  /// Matches the `delivery_failure_reason` enum in Postgres.
  String get wireValue => switch (this) {
    DeliveryFailureReason.customerAbsent => 'customer_absent',
    DeliveryFailureReason.customerRefused => 'customer_refused',
    DeliveryFailureReason.wrongAddress => 'wrong_address',
    DeliveryFailureReason.unreachable => 'unreachable',
    DeliveryFailureReason.packageIssue => 'package_issue',
    DeliveryFailureReason.other => 'other',
  };

  /// What a rider taps. Written from their side of the handlebars - what
  /// they just experienced - rather than as a category name.
  String get riderLabel => switch (this) {
    DeliveryFailureReason.customerAbsent => 'Nobody was there',
    DeliveryFailureReason.customerRefused => 'They refused it',
    DeliveryFailureReason.wrongAddress => 'Address is wrong',
    DeliveryFailureReason.unreachable => "Couldn't reach them",
    DeliveryFailureReason.packageIssue => 'Problem with the package',
    DeliveryFailureReason.other => 'Something else',
  };

  /// The same fact in a report, where it is being counted rather than
  /// tapped.
  String get label => switch (this) {
    DeliveryFailureReason.customerAbsent => 'Customer absent',
    DeliveryFailureReason.customerRefused => 'Refused',
    DeliveryFailureReason.wrongAddress => 'Wrong address',
    DeliveryFailureReason.unreachable => 'Unreachable',
    DeliveryFailureReason.packageIssue => 'Package problem',
    DeliveryFailureReason.other => 'Other',
  };

  /// One line under the option, so a rider picks the one that is actually
  /// true instead of whichever is nearest their thumb. These distinctions
  /// are the whole value of the data.
  String get hint => switch (this) {
    DeliveryFailureReason.customerAbsent =>
      'You got there and found nobody to hand it to.',
    DeliveryFailureReason.customerRefused =>
      'You found them and they would not take it.',
    DeliveryFailureReason.wrongAddress =>
      'The place does not exist, or nobody there knows them.',
    DeliveryFailureReason.unreachable =>
      'Phone off or no answer, so you could not find them.',
    DeliveryFailureReason.packageIssue =>
      'Damaged, the wrong item, or nothing to collect.',
    DeliveryFailureReason.other => 'Tell us what happened below.',
  };

  IconData get icon => switch (this) {
    DeliveryFailureReason.customerAbsent => Icons.door_front_door_outlined,
    DeliveryFailureReason.customerRefused => Icons.front_hand_outlined,
    DeliveryFailureReason.wrongAddress => Icons.wrong_location_outlined,
    DeliveryFailureReason.unreachable => Icons.phone_disabled_outlined,
    DeliveryFailureReason.packageIssue => Icons.inventory_2_outlined,
    DeliveryFailureReason.other => Icons.more_horiz,
  };
}
