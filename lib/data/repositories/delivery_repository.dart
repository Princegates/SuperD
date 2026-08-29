import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/delivery.dart';
import '../../models/delivery_incident.dart';
import '../../models/delivery_status.dart';

class DeliveryRepository {
  DeliveryRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'deliveries';
  static const _podBucket = 'proof-of-delivery';

  /// All deliveries, newest first. Used by the dispatcher dashboard.
  Stream<List<Delivery>> watchAllDeliveries() {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Delivery.fromMap).toList());
  }

  /// Only the deliveries assigned to [driverId]. Used by the driver
  /// dashboard - a completed/cancelled one has its pickup (vendor) details
  /// stripped, see [Delivery.withPickupHiddenIfHistory].
  Stream<List<Delivery>> watchDriverDeliveries(String driverId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('assigned_driver_id', driverId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map(Delivery.fromMap)
              .map((d) => d.withPickupHiddenIfHistory)
              .toList(),
        );
  }

  Stream<Delivery?> watchById(String id) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => rows.isEmpty ? null : Delivery.fromMap(rows.first));
  }

  Future<Delivery> fetchById(String id) async {
    final row = await _client.from(_table).select().eq('id', id).single();
    return Delivery.fromMap(row);
  }

  Future<String> createDelivery({
    required String customerName,
    String? customerPhone,
    String? customerEmail,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    required String dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? packageDescription,
    String? notes,
    required String createdBy,
    String? assignedDriverId,
    DateTime? scheduledAt,
  }) async {
    final row = await _client
        .from(_table)
        .insert({
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'customer_email': customerEmail,
          'pickup_address': pickupAddress,
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'dropoff_address': dropoffAddress,
          'dropoff_lat': dropoffLat,
          'dropoff_lng': dropoffLng,
          'package_description': packageDescription,
          'notes': notes,
          'created_by': createdBy,
          'assigned_driver_id': assignedDriverId,
          'scheduled_at': scheduledAt?.toIso8601String(),
          'status': assignedDriverId == null
              ? DeliveryStatus.pending.wireValue
              : DeliveryStatus.assigned.wireValue,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> assignDriver({
    required String deliveryId,
    required String? driverId,
  }) async {
    await _client
        .from(_table)
        .update({
          'assigned_driver_id': driverId,
          'status': driverId == null
              ? DeliveryStatus.pending.wireValue
              : DeliveryStatus.assigned.wireValue,
        })
        .eq('id', deliveryId);
  }

  /// Corrects a delivery's zone by hand - e.g. automatic detection got it
  /// wrong, or a dispatcher just disagrees. Doesn't retroactively re-price
  /// or reassign anything already done; it only affects driver-suggestion
  /// matching and zone reporting going forward. See
  /// `0040_zone_detection_radius_and_override.sql`.
  Future<void> setZone({
    required String deliveryId,
    required String? zoneId,
  }) async {
    await _client.from(_table).update({'zone_id': zoneId}).eq('id', deliveryId);
  }

  Future<void> updateStatus({
    required String deliveryId,
    required DeliveryStatus status,
  }) async {
    await _client
        .from(_table)
        .update({'status': status.wireValue})
        .eq('id', deliveryId);
  }

  Future<void> cancel(String deliveryId) =>
      updateStatus(deliveryId: deliveryId, status: DeliveryStatus.cancelled);

  /// Permanently erases the delivery record itself - not the same as
  /// [cancel], which keeps the record but marks it 'cancelled'. Only a
  /// super admin's request actually goes through - enforced by RLS (see
  /// `0035_super_admin_delete_deliveries.sql`), not just this client.
  /// Its status history and recorded payment go with it (cascade); any
  /// commission or SMS log entry stays, with this delivery unlinked.
  Future<void> deleteDelivery(String deliveryId) async {
    await _client.from(_table).delete().eq('id', deliveryId);
  }

  /// Sends a delivery that's assigned to the calling driver, but not yet
  /// accepted (still 'assigned' - before "Accept & begin trip"), back to
  /// the unassigned pool for a dispatcher to give to someone else. Goes
  /// through the `driver_reject_delivery` RPC rather than a plain table
  /// update, since `assigned_driver_id` is otherwise locked against
  /// anyone but a dispatcher - see `enforce_delivery_update()` in
  /// `0023_driver_reject_and_undo.sql`.
  Future<void> rejectDelivery(String deliveryId) async {
    await _client.rpc(
      'driver_reject_delivery',
      params: {'p_delivery_id': deliveryId},
    );
  }

  /// A driver who already accepted a delivery (`picked_up`/`in_transit`)
  /// but can't finish it hands it off instead of leaving it stuck assigned
  /// to them - tries another driver in the same zone first, falling back
  /// to the unassigned pool if nobody qualifies. Either way it's recorded
  /// with a full explanation (see [fetchIncidents]) and an admin is
  /// alerted by email/SMS - see `driver_cancel_delivery()` in
  /// `0036_driver_cancel_and_incident_reporting.sql`.
  Future<void> cancelTrip(String deliveryId, {String? reason}) async {
    await _client.rpc(
      'driver_cancel_delivery',
      params: {'p_delivery_id': deliveryId, 'p_reason': reason},
    );
  }

  Future<void> setNotes({
    required String deliveryId,
    required String notes,
  }) async {
    await _client.from(_table).update({'notes': notes}).eq('id', deliveryId);
  }

  /// Uploads a proof-of-delivery photo and stores its public URL on the
  /// delivery row.
  Future<String> uploadProofOfDelivery({
    required String deliveryId,
    required File file,
  }) async {
    final ext = file.path.split('.').last;
    final path = '$deliveryId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage
        .from(_podBucket)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));

    final publicUrl = _client.storage.from(_podBucket).getPublicUrl(path);

    await _client
        .from(_table)
        .update({'proof_of_delivery_url': publicUrl})
        .eq('id', deliveryId);

    return publicUrl;
  }

  Future<List<Map<String, dynamic>>> fetchStatusHistory(
    String deliveryId,
  ) async {
    return _client
        .from('delivery_status_history')
        .select()
        .eq('delivery_id', deliveryId)
        .order('created_at');
  }

  /// Every driver-rejected or driver-cancelled delivery ever recorded -
  /// the raw data behind the Console's "Rejections & cancellations" feed.
  /// Only rows with a note are these two events; every ordinary status
  /// change leaves `note` null and is filtered out here rather than in
  /// Dart, since that's the vast majority of the table.
  Future<List<DeliveryIncident>> fetchIncidents({int limit = 30}) async {
    final rows = await _client
        .from('delivery_status_history')
        .select()
        .not('note', 'is', null)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(DeliveryIncident.fromMap).toList();
  }
}
