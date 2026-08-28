/// One row of `delivery_status_history` where a driver rejected or
/// cancelled a delivery - the only rows with a non-null `note` (see
/// `0036_driver_cancel_and_incident_reporting.sql`). `driverId` is
/// whoever made the change (`changed_by`); resolving it to a display name
/// and the delivery's tracking code both happen client-side against
/// already-fetched provider data, the same way the Commission tab
/// resolves driver names - see `driversListProvider`/`allDeliveriesProvider`.
class DeliveryIncident {
  const DeliveryIncident({
    required this.deliveryId,
    required this.status,
    required this.note,
    required this.createdAt,
    this.driverId,
  });

  final String deliveryId;
  final String status;
  final String note;
  final DateTime createdAt;
  final String? driverId;

  factory DeliveryIncident.fromMap(Map<String, dynamic> map) {
    return DeliveryIncident(
      deliveryId: map['delivery_id'] as String,
      status: map['status'] as String? ?? '',
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      driverId: map['changed_by'] as String?,
    );
  }
}
