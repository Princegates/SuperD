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
  final String? email;
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
    this.email,
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
      email: map['email'] as String?,
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

/// The tracking code and server-quoted price returned by
/// `submit_delivery_request` - see `0022_delivery_pricing.sql`. The amount
/// is computed there (base fare + distance charge), never trusted from the
/// client.
class DeliveryQuote {
  final String trackingCode;
  final double amount;
  final String currency;

  const DeliveryQuote({
    required this.trackingCode,
    required this.amount,
    required this.currency,
  });

  factory DeliveryQuote.fromMap(Map<String, dynamic> map) {
    return DeliveryQuote(
      trackingCode: map['tracking_code'] as String? ?? '',
      amount: (map['quoted_amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'GHS',
    );
  }
}

/// The pricing rates a customer's request would be quoted at, returned by
/// the anonymous-safe `get_pricing_config()` RPC - used for a live
/// estimate on the request form before submitting.
class PricingConfig {
  final double baseFare;
  final double pricePerKm;
  final String currency;

  const PricingConfig({
    required this.baseFare,
    required this.pricePerKm,
    required this.currency,
  });

  factory PricingConfig.fromMap(Map<String, dynamic> map) {
    return PricingConfig(
      baseFare: (map['base_fare'] as num?)?.toDouble() ?? 5,
      pricePerKm: (map['price_per_km'] as num?)?.toDouble() ?? 1.5,
      currency: map['currency'] as String? ?? 'GHS',
    );
  }
}
