import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geocode_search.dart';

/// Address suggestions via Google's Places API (New) Autocomplete, through
/// the `google-places-autocomplete` Edge Function - the API key stays
/// server-side, never shipped to this client build. The paid alternative
/// to [searchAddress]'s free Nominatim path; same signature so
/// [AddressAutocompleteField] can be pointed at either one.
///
/// Results carry a [GeocodeResult.placeId] but no [GeocodeResult.location]
/// - Google only returns coordinates from a separate Place Details call
/// (see [resolvePlaceLocationGoogle]), which is what [sessionToken] is for:
/// reusing the same token across a whole typing sequence and its final
/// selection groups them into one billed session instead of paying for
/// every keystroke and the details call separately.
Future<List<GeocodeResult>> searchAddressGoogle(
  SupabaseClient client,
  String query, {
  String? sessionToken,
}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  try {
    final response = await client.functions.invoke(
      'google-places-autocomplete',
      body: {'query': trimmed, 'sessionToken': sessionToken},
    );
    final suggestions =
        (response.data as Map<String, dynamic>)['suggestions'] as List;
    return suggestions
        .map((row) {
          final map = row as Map<String, dynamic>;
          final description = map['description'] as String?;
          final placeId = map['placeId'] as String?;
          if (description == null || placeId == null) return null;
          return GeocodeResult(displayName: description, placeId: placeId);
        })
        .whereType<GeocodeResult>()
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Resolves a Google suggestion's coordinates once it's actually picked -
/// see `google-place-details`. Pass the same [sessionToken] the
/// suggestion came from, so this call terminates that session instead of
/// starting a new billed one. Null on any failure - the caller is left
/// with the address text but no coordinate, same as any other lookup
/// failure elsewhere in these forms.
Future<LatLng?> resolvePlaceLocationGoogle(
  SupabaseClient client,
  String placeId, {
  String? sessionToken,
}) async {
  try {
    final response = await client.functions.invoke(
      'google-place-details',
      body: {'placeId': placeId, 'sessionToken': sessionToken},
    );
    final data = response.data as Map<String, dynamic>;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  } catch (_) {
    return null;
  }
}
