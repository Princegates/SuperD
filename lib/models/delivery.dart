import 'delivery_status.dart';

class Delivery {
  final String id;
  final String trackingCode;
  final DeliveryStatus status;

  final String customerName;
  final String? customerPhone;

  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;

  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;

  final String? packageDescription;
  final String? notes;
  final String? proofOfDeliveryUrl;

  final String? createdBy;
  final String? assignedDriverId;
  final String? vendorId;
  final String? zoneId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  /// When the customer wants this delivered - null means as soon as
  /// possible (the default before scheduling existed).
  final DateTime? scheduledAt;

  const Delivery({
    required this.id,
    required this.trackingCode,
    required this.status,
    required this.customerName,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.customerPhone,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.packageDescription,
    this.notes,
    this.proofOfDeliveryUrl,
    this.assignedDriverId,
    this.vendorId,
    this.zoneId,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.scheduledAt,
  });

  factory Delivery.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.parse(v as String);

    return Delivery(
      id: map['id'] as String,
      trackingCode: map['tracking_code'] as String? ?? '',
      status: DeliveryStatus.fromString(map['status'] as String? ?? 'pending'),
      customerName: map['customer_name'] as String? ?? '',
      customerPhone: map['customer_phone'] as String?,
      pickupAddress: map['pickup_address'] as String? ?? '',
      pickupLat: (map['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (map['pickup_lng'] as num?)?.toDouble(),
      dropoffAddress: map['dropoff_address'] as String? ?? '',
      dropoffLat: (map['dropoff_lat'] as num?)?.toDouble(),
      dropoffLng: (map['dropoff_lng'] as num?)?.toDouble(),
      packageDescription: map['package_description'] as String?,
      notes: map['notes'] as String?,
      proofOfDeliveryUrl: map['proof_of_delivery_url'] as String?,
      createdBy: map['created_by'] as String?,
      assignedDriverId: map['assigned_driver_id'] as String?,
      vendorId: map['vendor_id'] as String?,
      zoneId: map['zone_id'] as String?,
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: parseDate(map['updated_at']) ?? DateTime.now(),
      assignedAt: parseDate(map['assigned_at']),
      pickedUpAt: parseDate(map['picked_up_at']),
      deliveredAt: parseDate(map['delivered_at']),
      scheduledAt: parseDate(map['scheduled_at']),
    );
  }

  bool get hasPickupCoordinates => pickupLat != null && pickupLng != null;
  bool get hasDropoffCoordinates => dropoffLat != null && dropoffLng != null;

  /// Still needs a driver (or hasn't been picked up yet) and its scheduled
  /// time is within [threshold] of now - the condition the animated
  /// dispatch reminder on the admin dashboard watches for.
  bool isDueSoon(Duration threshold, {DateTime? now}) {
    final scheduled = scheduledAt;
    if (scheduled == null) return false;
    if (status != DeliveryStatus.pending && status != DeliveryStatus.assigned) {
      return false;
    }
    final n = now ?? DateTime.now();
    return !scheduled.isBefore(n.subtract(const Duration(minutes: 1))) &&
        scheduled.isBefore(n.add(threshold));
  }

  /// True once the scheduled time has passed and it's still not out for
  /// delivery - an overdue dispatch, not just "coming up soon".
  bool isOverdue({DateTime? now}) {
    final scheduled = scheduledAt;
    if (scheduled == null) return false;
    if (status != DeliveryStatus.pending && status != DeliveryStatus.assigned) {
      return false;
    }
    return scheduled.isBefore(now ?? DateTime.now());
  }
}
