/// A vendor as seen by dispatchers/super admins managing the roster.
class Vendor {
  final String id;
  final String code;
  final String vendorName;
  final String? zoneId;
  final String? zoneName;
  final double? locationLat;
  final double? locationLng;
  final String phone;
  final bool isActive;
  final DateTime createdAt;

  const Vendor({
    required this.id,
    required this.code,
    required this.vendorName,
    required this.phone,
    required this.createdAt,
    this.zoneId,
    this.zoneName,
    this.locationLat,
    this.locationLng,
    this.isActive = true,
  });

  factory Vendor.fromMap(Map<String, dynamic> map) {
    final zone = map['zones'] as Map<String, dynamic>?;
    return Vendor(
      id: map['id'] as String,
      code: map['code'] as String,
      vendorName: map['vendor_name'] as String? ?? '',
      zoneId: map['zone_id'] as String?,
      zoneName: zone?['name'] as String?,
      locationLat: (map['location_lat'] as num?)?.toDouble(),
      locationLng: (map['location_lng'] as num?)?.toDouble(),
      phone: map['phone'] as String? ?? '',
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// Public-facing vendor info, returned by the `get_vendor_by_code` RPC -
/// only what a customer needs to see before filling in the request form.
class VendorPublicInfo {
  final String id;
  final String vendorName;
  final String? zoneName;
  final double? locationLat;
  final double? locationLng;
  final bool isActive;

  const VendorPublicInfo({
    required this.id,
    required this.vendorName,
    required this.isActive,
    this.zoneName,
    this.locationLat,
    this.locationLng,
  });

  factory VendorPublicInfo.fromMap(Map<String, dynamic> map) {
    return VendorPublicInfo(
      id: map['id'] as String,
      vendorName: map['vendor_name'] as String? ?? '',
      zoneName: map['zone_name'] as String?,
      locationLat: (map['location_lat'] as num?)?.toDouble(),
      locationLng: (map['location_lng'] as num?)?.toDouble(),
      isActive: map['is_active'] as bool? ?? false,
    );
  }
}

/// One row of a vendor's own order history, returned by the
/// `get_vendor_deliveries` RPC.
class VendorDelivery {
  final String id;
  final String trackingCode;
  final String status;
  final String customerName;
  final String dropoffAddress;
  final String? driverName;
  final String? driverPhone;
  final DateTime createdAt;

  const VendorDelivery({
    required this.id,
    required this.trackingCode,
    required this.status,
    required this.customerName,
    required this.dropoffAddress,
    required this.createdAt,
    this.driverName,
    this.driverPhone,
  });

  factory VendorDelivery.fromMap(Map<String, dynamic> map) {
    return VendorDelivery(
      id: map['id'] as String,
      trackingCode: map['tracking_code'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      customerName: map['customer_name'] as String? ?? '',
      dropoffAddress: map['dropoff_address'] as String? ?? '',
      driverName: map['driver_name'] as String?,
      driverPhone: map['driver_phone'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
