import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/vendor.dart';
import '../../models/zone.dart';
import '../../models/zone_location.dart';
import '../../shared/utils/resilient_stream.dart';

/// Zones (for grouping drivers/vendors) and vendors (the businesses whose
/// customers request deliveries through a unique link, with no SuperD
/// account of their own). The public-facing pieces - registering as a
/// vendor, submitting a delivery request, and a vendor checking their own
/// orders - all go through SECURITY DEFINER Postgres functions rather than
/// direct table access, since those need to work with no session at all.
class VendorRepository {
  VendorRepository(this._client);

  final SupabaseClient _client;

  Future<List<Zone>> fetchZones() async {
    final rows = await _client.from('zones').select().order('name');
    return rows.map(Zone.fromMap).toList();
  }

  /// Super-admin only - enforced by RLS on `zones`.
  Future<void> createZone(String name) async {
    await _client.from('zones').insert({'name': name});
  }

  /// Super-admin only - enforced by RLS on `zones`.
  Future<void> renameZone(String id, String name) async {
    await _client.from('zones').update({'name': name}).eq('id', id);
  }

  /// Super-admin only - enforced by RLS on `zones`. Postgres rejects this
  /// with a foreign-key-violation if any vendor, driver, or delivery still
  /// references the zone (no `on delete cascade`) - callers should catch
  /// that and tell the admin to reassign those first.
  Future<void> deleteZone(String id) async {
    await _client.from('zones').delete().eq('id', id);
  }

  /// The named places a super admin has added to [zoneId] - reference
  /// data for the Console's Zones tab, not something a driver/vendor
  /// dropdown needs.
  Future<List<ZoneLocation>> fetchZoneLocations(String zoneId) async {
    final rows = await _client
        .from('zone_locations')
        .select()
        .eq('zone_id', zoneId)
        .order('name');
    return rows.map(ZoneLocation.fromMap).toList();
  }

  /// Super-admin only - enforced by RLS on `zone_locations`.
  Future<void> addZoneLocation({
    required String zoneId,
    required String name,
    double? lat,
    double? lng,
  }) async {
    await _client.from('zone_locations').insert({
      'zone_id': zoneId,
      'name': name,
      'lat': lat,
      'lng': lng,
    });
  }

  /// Adds many named locations to a zone in one round trip - the fast
  /// path for building out a zone's coverage (which also directly
  /// improves how accurately `detect_zone_for_point()` can recognize a
  /// customer's drop-off zone - see `0033_zone_auto_recognition_and_cap.sql`)
  /// instead of the one-at-a-time "pin on map" flow. Super-admin only -
  /// enforced by RLS on `zone_locations`.
  Future<void> addZoneLocationsBatch({
    required String zoneId,
    required List<({String name, double lat, double lng})> locations,
  }) async {
    if (locations.isEmpty) return;
    await _client.from('zone_locations').insert([
      for (final loc in locations)
        {'zone_id': zoneId, 'name': loc.name, 'lat': loc.lat, 'lng': loc.lng},
    ]);
  }

  /// Super-admin only - enforced by RLS on `zone_locations`.
  Future<void> deleteZoneLocation(String id) async {
    await _client.from('zone_locations').delete().eq('id', id);
  }

  /// Dispatcher/super-admin edit of an existing vendor's details - direct
  /// table update (RLS already allows this for `is_dispatcher_or_above()`),
  /// unlike registration which goes through the `register_vendor` function.
  Future<void> updateVendor({
    required String id,
    required String vendorName,
    required String phone,
    String? zoneId,
    double? locationLat,
    double? locationLng,
    String? email,
  }) async {
    await _client
        .from('vendors')
        .update({
          'vendor_name': vendorName,
          'phone': phone,
          'zone_id': zoneId,
          'email': email,
          'location_lat': ?locationLat,
          'location_lng': ?locationLng,
        })
        .eq('id', id);
  }

  /// Activating/deactivating a vendor's link - an inactive vendor's link
  /// stops accepting new delivery requests (`submit_delivery_request`
  /// checks `is_active`), but their existing orders and tracking page keep
  /// working.
  Future<void> setVendorActive(String id, bool isActive) async {
    await _client.from('vendors').update({'is_active': isActive}).eq('id', id);
  }

  /// Permanently removes a vendor - dispatcher/super-admin only (RLS on
  /// `vendors`). Postgres rejects this with a foreign-key-violation
  /// (`23503`) if any delivery still references the vendor - same
  /// protection as [deleteZone] - so their order history can't be
  /// deleted out from under it; deactivate instead if that's what's
  /// actually needed.
  Future<void> deleteVendor(String id) async {
    await _client.from('vendors').delete().eq('id', id);
  }

  /// Every vendor, for the dispatcher/super-admin Vendors screen.
  Future<List<Vendor>> fetchVendors() async {
    final rows = await _client
        .from('vendors')
        .select('*, zones(name)')
        .order('created_at', ascending: false);
    return rows.map(Vendor.fromMap).toList();
  }

  /// Every vendor, live - just for the admin shell's "new vendor
  /// registered" in-app notification, so it doesn't need the Vendors
  /// screen open to fire. `.stream()` can't do the `zones(name)` join
  /// [fetchVendors] does, but a notification only needs the vendor's name
  /// anyway - `Vendor.fromMap` already tolerates a missing `zones` key.
  Stream<List<Vendor>> watchVendorRegistrations() {
    return resilientRealtimeStream(
      () => _client
          .from('vendors')
          .stream(primaryKey: ['id'])
          .order('created_at')
          .map((rows) => rows.map(Vendor.fromMap).toList()),
    );
  }

  /// Registers a vendor and returns their unique code (their link is
  /// `/v/<code>`, which also doubles as their order-tracking link). Used
  /// both by the dispatcher/super-admin "Add vendor" screen (pass
  /// [createdBy]) and by the public self-service signup form (leave it
  /// null) - same underlying `register_vendor` function either way.
  ///
  /// [email], when given, gets the vendor their link by email automatically
  /// - see `notify-vendor-registered` (a Database Webhook on this table's
  /// insert, documented in the README).
  ///
  /// Returns two SEPARATE secrets: [VendorRegistration.code] is the public
  /// link to share with customers, and [VendorRegistration.ordersCode] is
  /// a private one for the vendor's own "view all my orders" page - never
  /// give that one to a customer, or they can see every other customer's
  /// order for this vendor too. See `0027_separate_vendor_orders_code.sql`.
  Future<VendorRegistration> registerVendor({
    required String vendorName,
    required double locationLat,
    required double locationLng,
    required String phone,
    String? zoneId,
    String? email,
    String? createdBy,
  }) async {
    final rows = await _client.rpc(
      'register_vendor',
      params: {
        'vendor_name': vendorName,
        'zone_id': zoneId,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'phone': phone,
        'email': email,
        'created_by': createdBy,
      },
    ) as List;
    return VendorRegistration.fromMap(rows.first as Map<String, dynamic>);
  }

  /// Registers a vendor from the PUBLIC self-service signup form - unlike
  /// [registerVendor] (still used as-is by the dispatcher/super-admin "Add
  /// vendor" screen, an authenticated caller with no anti-bot need), this
  /// goes through the `public-register-vendor` Edge Function instead of
  /// calling `register_vendor` directly - anon's own execute grant on
  /// that function was revoked in `0059_public_form_captcha_gate.sql`,
  /// once this project has a Cloudflare Turnstile secret configured that
  /// function refuses to run without a verified [turnstileToken]. See the
  /// README's "Public form protection" section - a project that hasn't
  /// set that up yet ignores [turnstileToken] entirely and behaves
  /// exactly as before.
  Future<VendorRegistration> registerVendorPublic({
    required String vendorName,
    required double locationLat,
    required double locationLng,
    required String phone,
    String? zoneId,
    String? email,
    String? turnstileToken,
    required String termsVersion,
  }) async {
    final response = await _client.functions.invoke(
      'public-register-vendor',
      body: {
        'vendorName': vendorName,
        'zoneId': zoneId,
        'locationLat': locationLat,
        'locationLng': locationLng,
        'phone': phone,
        'email': email,
        'turnstileToken': turnstileToken,
        'termsVersion': termsVersion,
      },
    );
    return VendorRegistration.fromMap(response.data as Map<String, dynamic>);
  }

  /// Starts a real-time Mobile Money charge for [code]'s one-time
  /// subscription fee via the "paystack-vendor-subscription-charge" Edge
  /// Function - the vendor approves a prompt on their phone, and their
  /// link activates itself once Paystack's webhook resolves it (poll
  /// [fetchVendorByCode] to notice). Public - a vendor has no login, only
  /// their own [code] - the actual amount owed is always looked up
  /// server-side, never trusted from this client. Throws
  /// [VendorSubscriptionException] if [code] isn't in a chargeable state
  /// (already active, no fee applies, or the feature's since been turned
  /// off).
  Future<String> payVendorSubscription({
    required String code,
    required String phone,
    required String network,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'paystack-vendor-subscription-charge',
        body: {'code': code, 'phone': phone, 'network': network},
      );
      final data = response.data as Map<String, dynamic>;
      return data['message'] as String? ??
          'Check your phone to approve the payment.';
    } on FunctionException catch (e) {
      throw VendorSubscriptionException(_messageFrom(e));
    }
  }

  /// Looks up a vendor by their public code - null if it doesn't exist.
  Future<VendorPublicInfo?> fetchVendorByCode(String code) async {
    final rows = await _client.rpc(
      'get_vendor_by_code',
      params: {'p_code': code},
    ) as List;
    if (rows.isEmpty) return null;
    return VendorPublicInfo.fromMap(rows.first as Map<String, dynamic>);
  }

  /// Creates a pending delivery on behalf of a customer who opened a
  /// vendor's link - no login required. Returns the tracking code plus the
  /// price quoted server-side (see `submit_delivery_request` in
  /// `0028_road_distance_pricing.sql` - base fare + distance charge,
  /// computed there rather than trusted from the client). [roadDistanceKm],
  /// when given (see [fetchRoadDistanceKm]), prices by real road distance
  /// instead of straight-line - the server still enforces a straight-line
  /// floor either way, so this can never be used to under-report distance.
  ///
  /// Goes through the `public-submit-delivery-request` Edge Function
  /// rather than calling `submit_delivery_request` directly - anon's own
  /// execute grant on that function was revoked in
  /// `0059_public_form_captcha_gate.sql`, once this project has a
  /// Cloudflare Turnstile secret configured that function refuses to run
  /// without a verified [turnstileToken]. See the README's "Public form
  /// protection" section - a project that hasn't set that up yet ignores
  /// [turnstileToken] entirely and behaves exactly as before.
  Future<DeliveryQuote> submitDeliveryRequest({
    required String code,
    required String customerName,
    required String customerPhone,
    required String dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? packageDescription,
    double? roadDistanceKm,
    DateTime? scheduledAt,
    String? customerEmail,
    String? vehicleTypeId,
    String? turnstileToken,
  }) async {
    final response = await _client.functions.invoke(
      'public-submit-delivery-request',
      body: {
        'code': code,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'dropoffAddress': dropoffAddress,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'packageDescription': packageDescription,
        'roadDistanceKm': roadDistanceKm,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'customerEmail': customerEmail,
        'vehicleTypeId': vehicleTypeId,
        'turnstileToken': turnstileToken,
      },
    );
    return DeliveryQuote.fromMap(response.data as Map<String, dynamic>);
  }

  /// A low-high price range for [code]'s vendor, optionally narrowed by a
  /// drop-off location - for showing a live estimate on the request form
  /// before a customer submits. Anonymous-safe, zone-aware, with no upper
  /// bound - see `get_delivery_price_estimate()` in
  /// `0051_vehicle_types.sql`. [roadDistanceKm]/[vehicleTypeId] - see
  /// [submitDeliveryRequest].
  Future<PriceEstimate> fetchPriceEstimate({
    required String code,
    double? dropoffLat,
    double? dropoffLng,
    double? roadDistanceKm,
    String? vehicleTypeId,
  }) async {
    final rows = await _client.rpc(
      'get_delivery_price_estimate',
      params: {
        'p_code': code,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'road_distance_km': roadDistanceKm,
        'p_vehicle_type_id': vehicleTypeId,
      },
    ) as List;
    return PriceEstimate.fromMap(rows.first as Map<String, dynamic>);
  }

  /// The real driving distance (km) between two points, via Google's
  /// Directions API - called through the `get-road-distance` Edge
  /// Function so the Directions API key never ships to any client. Null
  /// on any failure (no route, network error, key not configured) so
  /// callers fall back to the server's own straight-line calculation -
  /// see `0028_road_distance_pricing.sql`.
  Future<double?> fetchRoadDistanceKm({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'get-road-distance',
        body: {
          'originLat': originLat,
          'originLng': originLng,
          'destLat': destLat,
          'destLng': destLng,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return (data['distanceKm'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Super-admin only (enforced by RLS on `zones`) - sets or clears a
  /// zone's own pricing rates. Null clears the override, falling back to
  /// the app-wide default from Console > Settings.
  Future<void> updateZonePricing({
    required String zoneId,
    double? baseFare,
    double? pricePerKm,
  }) async {
    await _client
        .from('zones')
        .update({'base_fare': baseFare, 'price_per_km': pricePerKm})
        .eq('id', zoneId);
  }

  /// A vendor's own order history - powers their private orders page.
  /// [ordersCode] is the vendor's own secret (never the public [code] a
  /// customer receives) - see `0027_separate_vendor_orders_code.sql`.
  Future<List<VendorDelivery>> fetchVendorDeliveries(String ordersCode) async {
    final rows = await _client.rpc(
      'get_vendor_deliveries',
      params: {'p_orders_code': ordersCode},
    ) as List;
    return rows
        .map((row) => VendorDelivery.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Live version of [fetchVendorDeliveries], so a vendor sees a status
  /// change (assigned, picked up, delivered) without pulling to refresh.
  /// This is polled rather than true Postgres realtime - the page is
  /// anonymous/no-login, and `deliveries` has no anon read policy at all
  /// (only this scoped RPC), so there's no table to subscribe to without
  /// opening up direct access that would let anyone enumerate other
  /// vendors' orders.
  Stream<List<VendorDelivery>> watchVendorDeliveries(String ordersCode) async* {
    while (true) {
      yield await fetchVendorDeliveries(ordersCode);
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  /// A single delivery, scoped to the tracking code a customer was given
  /// when they submitted it - never the vendor's full order list, so one
  /// customer can never see another's order this way. Null if the code
  /// doesn't match anything. See `get_delivery_by_tracking_code()` in
  /// `0027_separate_vendor_orders_code.sql`.
  Future<VendorDelivery?> fetchDeliveryByTrackingCode(
    String trackingCode,
  ) async {
    final rows = await _client.rpc(
      'get_delivery_by_tracking_code',
      params: {'p_tracking_code': trackingCode},
    ) as List;
    if (rows.isEmpty) return null;
    return VendorDelivery.fromMap(rows.first as Map<String, dynamic>);
  }

  /// Live version of [fetchDeliveryByTrackingCode] - same polling
  /// approach as [watchVendorDeliveries].
  Stream<VendorDelivery?> watchDeliveryByTrackingCode(
    String trackingCode,
  ) async* {
    while (true) {
      yield await fetchDeliveryByTrackingCode(trackingCode);
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  /// A customer rates (or re-rates) the driver on their own delivery,
  /// scoped to the tracking code they were given - never anyone else's.
  /// Only accepted once the delivery is actually delivered - see
  /// `submit_delivery_rating()` in `0034_notifications_tracking_ratings.sql`.
  Future<void> submitDeliveryRating({
    required String trackingCode,
    required int rating,
    String? comment,
  }) async {
    await _client.rpc(
      'submit_delivery_rating',
      params: {
        'p_tracking_code': trackingCode,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
  }

  /// Re-sends a vendor's own link via just one channel - [channel] must be
  /// `'sms'` or `'email'` - via the "admin-resend-vendor-link" Edge
  /// Function, for a dispatcher/super admin to use when the original
  /// notify-vendor-registered message never arrived. Dispatcher-or-above
  /// only, enforced server-side.
  Future<void> resendVendorLink({
    required String vendorId,
    required String channel,
  }) async {
    try {
      await _client.functions.invoke(
        'admin-resend-vendor-link',
        body: {'vendorId': vendorId, 'channel': channel},
      );
    } on FunctionException catch (e) {
      throw VendorLinkException(_messageFrom(e));
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

/// Thrown when resending a vendor's link fails, with a message safe to
/// show directly to the dispatcher/super admin who triggered it.
class VendorLinkException implements Exception {
  VendorLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a vendor's one-time subscription charge fails, with a
/// message safe to show directly to the vendor on the signup page.
class VendorSubscriptionException implements Exception {
  VendorSubscriptionException(this.message);
  final String message;

  @override
  String toString() => message;
}
