/// A vendor's ask for a hand-priced special delivery on behalf of a
/// customer, submitted from their private orders page - not a delivery
/// yet. See `0099_vendor_special_delivery_requests.sql`. [vendorName] isn't
/// a column on this table - resolve it against the admin app's own
/// `vendorsProvider` list by [vendorId], the same way callers already have
/// vendor names on hand elsewhere, rather than losing this table's plain
/// Realtime stream to a join `.stream()` can't express.
class SpecialDeliveryRequest {
  final String id;
  final String vendorId;
  final String customerName;
  final String customerPhone;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? packageDescription;
  final String? notes;
  final String status;
  final String? fulfilledDeliveryId;
  final DateTime createdAt;

  const SpecialDeliveryRequest({
    required this.id,
    required this.vendorId,
    required this.customerName,
    required this.customerPhone,
    required this.dropoffAddress,
    required this.status,
    required this.createdAt,
    this.dropoffLat,
    this.dropoffLng,
    this.packageDescription,
    this.notes,
    this.fulfilledDeliveryId,
  });

  bool get isPending => status == 'pending';

  factory SpecialDeliveryRequest.fromMap(Map<String, dynamic> map) {
    return SpecialDeliveryRequest(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      customerName: map['customer_name'] as String,
      customerPhone: map['customer_phone'] as String,
      dropoffAddress: map['dropoff_address'] as String,
      dropoffLat: (map['dropoff_lat'] as num?)?.toDouble(),
      dropoffLng: (map['dropoff_lng'] as num?)?.toDouble(),
      packageDescription: map['package_description'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] as String,
      fulfilledDeliveryId: map['fulfilled_delivery_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
