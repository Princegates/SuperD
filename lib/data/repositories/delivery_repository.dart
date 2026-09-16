import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/delivery.dart';
import '../../models/delivery_failure_reason.dart';
import '../../models/delivery_incident.dart';
import '../../models/delivery_status.dart';
import '../../shared/utils/resilient_stream.dart';

class DeliveryRepository {
  DeliveryRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'deliveries';
  static const _podBucket = 'proof-of-delivery';

  /// How far back the live dispatch stream reaches.
  ///
  /// Dispatch is about what is happening now and what happened lately; a
  /// job from last spring belongs in reporting, not on a realtime feed
  /// that every dispatcher holds open all day. Generous on purpose - a
  /// stuck delivery is flagged within hours (see DeliveryIncident), so
  /// nothing operational is ever near this edge, and a wide window keeps
  /// the Deliveries screen's search useful.
  static const recentWindow = Duration(days: 90);

  /// Recent deliveries, newest first, live. What the dispatcher dashboard,
  /// the Drivers screen and the shell's notifications all read.
  ///
  /// Bounded rather than the whole table: this is a realtime subscription
  /// held open by every dispatcher, and it re-reads everything it covers
  /// on each reconnect - which `resilientRealtimeStream` does on any
  /// dropped socket. Unbounded, that cost grows with the delivery history
  /// forever, for a screen that only ever shows the top of it.
  ///
  /// One filter, because a realtime stream only takes one - hence a plain
  /// date cut rather than "active OR recent". A delivery still live after
  /// 90 days is a data problem, not a dispatch one.
  Stream<List<Delivery>> watchRecentDeliveries() {
    final cutoff = DateTime.now().toUtc().subtract(recentWindow);
    return resilientRealtimeStream(
      () => _client
          .from(_table)
          .stream(primaryKey: ['id'])
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false)
          .map((rows) => rows.map(Delivery.fromMap).toList()),
    );
  }

  /// Every delivery ever, newest first - one shot, no subscription.
  ///
  /// Reporting needs the lot: Console Reports offers a range going back
  /// five years and defaults to all of it, and a vendor's page shows
  /// lifetime totals. Those are read deliberately, by someone who opened a
  /// report, so they are a fetch rather than a live feed - the numbers do
  /// not need to move under the reader, and pulling the whole table into
  /// every dispatcher's session all day to serve them would be the same
  /// mistake in a different place.
  Future<List<Delivery>> fetchAllDeliveries() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return rows.map(Delivery.fromMap).toList();
  }

  /// Only the deliveries assigned to [driverId]. Used by the driver
  /// dashboard - a completed/cancelled one has its pickup (vendor) details
  /// stripped, see [Delivery.withPickupHiddenIfHistory].
  Stream<List<Delivery>> watchDriverDeliveries(String driverId) {
    return resilientRealtimeStream(
      () => _client
          .from(_table)
          .stream(primaryKey: ['id'])
          .eq('assigned_driver_id', driverId)
          .order('created_at', ascending: false)
          .map(
            (rows) => rows
                .map(Delivery.fromMap)
                .map((d) => d.withPickupHiddenIfHistory)
                .toList(),
          ),
    );
  }

  Stream<Delivery?> watchById(String id) {
    return resilientRealtimeStream(
      () => _client
          .from(_table)
          .stream(primaryKey: ['id'])
          .eq('id', id)
          .map((rows) => rows.isEmpty ? null : Delivery.fromMap(rows.first)),
    );
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
    String? vehicleTypeId,
    bool isSpecial = false,
    String? vendorId,
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
          'vehicle_type_id': vehicleTypeId,
          'is_special': isSpecial,
          'vendor_id': vendorId,
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

  /// The only way a driver can mark a delivery 'delivered' - a plain
  /// [updateStatus] call is rejected server-side for that specific
  /// transition (see `enforce_delivery_update()` in
  /// `0056_delivery_completion_pin.sql`). Verifies [pin] against the
  /// value texted/emailed to the customer when the driver picked the
  /// package up, throwing if it doesn't match.
  ///
  /// The RPC hands back a message rather than raising one, so that a wrong
  /// guess still commits the row counting it - see the note in
  /// `0083_harden_profile_self_service_and_pin.sql`. Null means it went
  /// through; anything else is already worded for the driver, and is
  /// rethrown as the [PostgrestException] this method's callers have
  /// always caught.
  Future<void> completeDeliveryWithPin({
    required String deliveryId,
    required String pin,
  }) async {
    final message = await _client.rpc(
      'complete_delivery_with_pin',
      params: {'p_delivery_id': deliveryId, 'p_pin': pin},
    );
    if (message != null && message.toString().trim().isNotEmpty) {
      throw PostgrestException(message: message.toString());
    }
  }

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

  /// Records that a rider went out and the parcel did not change hands.
  ///
  /// Not the same thing as [cancelTrip], which hands a job the rider
  /// cannot finish to somebody else - here the attempt was made and it
  /// did not work, so the delivery ends. See `fail_delivery()` in
  /// `0089_failed_delivery_outcome.sql`; the server decides who is
  /// allowed to record this, and refuses on a job already delivered or
  /// already failed.
  Future<void> failDelivery({
    required String deliveryId,
    required DeliveryFailureReason reason,
    String? note,
  }) async {
    await _client.rpc(
      'fail_delivery',
      params: {
        'p_delivery_id': deliveryId,
        'p_reason': reason.wireValue,
        'p_note': note,
      },
    );
  }

  Future<void> setNotes({
    required String deliveryId,
    required String notes,
  }) async {
    await _client.from(_table).update({'notes': notes}).eq('id', deliveryId);
  }

  /// Uploads a proof-of-delivery photo and records its path on the
  /// delivery row.
  ///
  /// A path, not a URL. The bucket is private as of 0098 - a delivery
  /// photo is taken at someone's door and shows their address, so an
  /// absolute link that never expires and needs no sign-in was the wrong
  /// shape for it. Readers mint a short-lived signed link instead; see
  /// [proofOfDeliveryUrl].
  Future<String> uploadProofOfDelivery({
    required String deliveryId,
    required File file,
  }) async {
    final ext = file.path.split('.').last;
    final path = '$deliveryId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage
        .from(_podBucket)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));

    await _client
        .from(_table)
        .update({'proof_of_delivery_url': path})
        .eq('id', deliveryId);

    return path;
  }

  /// A viewable link for one delivery's proof photo, valid for [ttl].
  ///
  /// Null rather than throwing when the photo is missing or unreadable -
  /// the screens that show it have a job to do either way, and a detail
  /// page that fails to load because one file went astray is worse than
  /// one with a gap where a photo would be.
  ///
  /// Tolerates a stored absolute URL as well as a path, in case a row
  /// predates 0098's rewrite or was written by a client still on an
  /// older build.
  Future<String?> proofOfDeliveryUrl(
    String? pathOrUrl, {
    Duration ttl = const Duration(hours: 1),
  }) async {
    if (pathOrUrl == null) return null;
    final path = pathOrUrl.contains('/$_podBucket/')
        ? pathOrUrl.split('/$_podBucket/').last
        : pathOrUrl;
    try {
      return await _client.storage
          .from(_podBucket)
          .createSignedUrl(path, ttl.inSeconds);
    } catch (_) {
      return null;
    }
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

  /// Re-sends a delivery's tracking link (SMS + email) to its customer via
  /// the "admin-resend-tracking-link" Edge Function - for a dispatcher/
  /// super admin to use when the original notify-delivery-events message
  /// never arrived. Dispatcher-or-above only, enforced server-side.
  Future<void> resendTrackingLink(String deliveryId) async {
    try {
      await _client.functions.invoke(
        'admin-resend-tracking-link',
        body: {'deliveryId': deliveryId},
      );
    } on FunctionException catch (e) {
      throw TrackingLinkException(_messageFrom(e));
    }
  }

  String _messageFrom(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong. Please try again.';
  }
}

/// Thrown when resending a tracking link fails, with a message safe to
/// show directly to the dispatcher/super admin who triggered it.
class TrackingLinkException implements Exception {
  TrackingLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}
