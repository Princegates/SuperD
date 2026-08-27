import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/vendor.dart';
import '../../models/zone.dart';
import '../../models/zone_location.dart';

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
    return _client
        .from('vendors')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map(Vendor.fromMap).toList());
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
  }) async {
    final rows = await _client.rpc(
      'submit_delivery_request',
      params: {
        'p_code': code,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'dropoff_address': dropoffAddress,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'package_description': packageDescription,
        'road_distance_km': roadDistanceKm,
        'scheduled_at': scheduledAt?.toIso8601String(),
      },
    ) as List;
    return DeliveryQuote.fromMap(rows.first as Map<String, dynamic>);
  }

  /// A low-high price range for [code]'s vendor, optionally narrowed by a
  /// drop-off location - for showing a live estimate on the request form
  /// before a customer submits. Anonymous-safe, zone-aware, and capped at
  /// 50 server-side - see `get_delivery_price_estimate()` in
  /// `0028_road_distance_pricing.sql`. [roadDistanceKm] - see
  /// [submitDeliveryRequest].
  Future<PriceEstimate> fetchPriceEstimate({
    required String code,
    double? dropoffLat,
    double? dropoffLng,
    double? roadDistanceKm,
  }) async {
    final rows = await _client.rpc(
      'get_delivery_price_estimate',
      params: {
        'p_code': code,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'road_distance_km': roadDistanceKm,
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
}
