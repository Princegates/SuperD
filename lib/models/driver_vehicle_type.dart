import 'package:flutter/material.dart';

/// What a driver delivers with - groups/filters the driver roster in Team,
/// and feeds the zone auto-assignment algorithm. See the `driver_vehicle_type`
/// Postgres enum in `0025_driver_categories_and_status.sql`.
enum DriverVehicleType {
  motorbike,
  car,
  vanTruck,
  tricycle;

  static DriverVehicleType? fromString(String? value) {
    return switch (value) {
      'motorbike' => DriverVehicleType.motorbike,
      'car' => DriverVehicleType.car,
      'van_truck' => DriverVehicleType.vanTruck,
      'tricycle' => DriverVehicleType.tricycle,
      _ => null,
    };
  }

  /// The value stored in Postgres (matches the `driver_vehicle_type` enum).
  String get wireValue => switch (this) {
    DriverVehicleType.motorbike => 'motorbike',
    DriverVehicleType.car => 'car',
    DriverVehicleType.vanTruck => 'van_truck',
    DriverVehicleType.tricycle => 'tricycle',
  };

  String get label => switch (this) {
    DriverVehicleType.motorbike => 'Motorbike',
    DriverVehicleType.car => 'Car',
    DriverVehicleType.vanTruck => 'Van / Truck',
    DriverVehicleType.tricycle => 'Tricycle',
  };

  IconData get icon => switch (this) {
    DriverVehicleType.motorbike => Icons.two_wheeler,
    DriverVehicleType.car => Icons.directions_car_outlined,
    DriverVehicleType.vanTruck => Icons.local_shipping_outlined,
    DriverVehicleType.tricycle => Icons.electric_rickshaw_outlined,
  };
}
