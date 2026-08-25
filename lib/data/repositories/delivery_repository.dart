import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/delivery.dart';
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

  /// Only the deliveries assigned to [driverId]. Used by the driver dashboard.
  Stream<List<Delivery>> watchDriverDeliveries(String driverId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('assigned_driver_id', driverId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Delivery.fromMap).toList());
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
  }) async {
    final row = await _client
        .from(_table)
        .insert({
          'customer_name': customerName,
          'customer_phone': customerPhone,
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
}
