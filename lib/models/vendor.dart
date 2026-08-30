/// The two secrets `register_vendor` hands back - a public [code] to share
/// with customers, and a private [ordersCode] for the vendor's own "view
/// all my orders" page. See `0027_separate_vendor_orders_code.sql`.
class VendorRegistration {
  final String code;
  final String ordersCode;

  const VendorRegistration({required this.code, required this.ordersCode});

  factory VendorRegistration.fromMap(Map<String, dynamic> map) {
    return VendorRegistration(
      code: map['code'] as String,
      ordersCode: map['orders_code'] as String,
    );
  }
}

/// A vendor as seen by dispatchers/super admins managing the roster.
class Vendor {
  final String id;
  final String code;

  /// A SEPARATE secret from [code] - only for this vendor's own "view all
  /// my orders" page. Never shown or sent to a customer - see
  /// `vendors.orders_code` in `0027_separate_vendor_orders_code.sql`.
  final String ordersCode;
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
    required this.ordersCode,
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
      ordersCode: map['orders_code'] as String? ?? '',
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

/// One row of a vendor's own order history (from `get_vendor_deliveries`)
/// or a customer's own tracked delivery (from
/// `get_delivery_by_tracking_code`) - the two functions return
/// overlapping but not identical columns, so every field beyond the
/// shared core is nullable and simply absent from whichever didn't
/// return it.
class VendorDelivery {
  final String id;
  final String trackingCode;
  final String status;
  final String customerName;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? driverName;
  final String? driverPhone;
  final double? driverLat;
  final double? driverLng;
  final DateTime? driverLocationUpdatedAt;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final int? rating;
  final String? ratingComment;

  /// The delivery-completion PIN (see 0056_delivery_completion_pin.sql),
  /// only ever non-null from `get_delivery_by_tracking_code()` - the
  /// customer's own public tracking page - and only while the delivery
  /// is actually `picked_up`/`in_transit`, matching the same reveal
  /// timing as the SMS/email notification. `get_vendor_deliveries()`
  /// never selects this column, so it's always null on a vendor's own
  /// order list, same as the driver's own app never seeing it.
  final String? completionPin;

  const VendorDelivery({
    required this.id,
    required this.trackingCode,
    required this.status,
    required this.customerName,
    required this.dropoffAddress,
    required this.createdAt,
    this.dropoffLat,
    this.dropoffLng,
    this.driverName,
    this.driverPhone,
    this.driverLat,
    this.driverLng,
    this.driverLocationUpdatedAt,
    this.scheduledAt,
    this.rating,
    this.ratingComment,
    this.completionPin,
  });

  factory VendorDelivery.fromMap(Map<String, dynamic> map) {
    return VendorDelivery(
      id: map['id'] as String,
      trackingCode: map['tracking_code'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      customerName: map['customer_name'] as String? ?? '',
      dropoffAddress: map['dropoff_address'] as String? ?? '',
      dropoffLat: (map['dropoff_lat'] as num?)?.toDouble(),
      dropoffLng: (map['dropoff_lng'] as num?)?.toDouble(),
      driverName: map['driver_name'] as String?,
      driverPhone: map['driver_phone'] as String?,
      driverLat: (map['driver_lat'] as num?)?.toDouble(),
      driverLng: (map['driver_lng'] as num?)?.toDouble(),
      driverLocationUpdatedAt: map['driver_location_updated_at'] == null
          ? null
          : DateTime.parse(map['driver_location_updated_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      scheduledAt: map['scheduled_at'] == null
          ? null
          : DateTime.parse(map['scheduled_at'] as String),
      rating: (map['rating'] as num?)?.toInt(),
      ratingComment: map['rating_comment'] as String?,
      completionPin: map['completion_pin'] as String?,
    );
  }

  bool get hasDriverLocation => driverLat != null && driverLng != null;
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

/// A low-high price range a customer's request would likely be quoted at,
/// returned by the anonymous-safe `get_delivery_price_estimate()` RPC - for
/// showing an estimate on the request form immediately as a drop-off
/// location is set, before submitting. Zone-aware, with no upper bound -
/// same as the real quote `submit_delivery_request` returns on actual
/// submission - see `0047_remove_price_cap.sql`.
class PriceEstimate {
  final double low;
  final double high;
  final String currency;

  const PriceEstimate({
    required this.low,
    required this.high,
    required this.currency,
  });

  factory PriceEstimate.fromMap(Map<String, dynamic> map) {
    return PriceEstimate(
      low: (map['low_amount'] as num?)?.toDouble() ?? 0,
      high: (map['high_amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'GHS',
    );
  }
}
