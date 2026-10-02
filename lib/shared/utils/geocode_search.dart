import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/app_identity.dart';

/// One address match from [searchAddress] or `searchAddressGoogle`
/// (`google_places_search.dart`). [location] is null only for a Google
/// suggestion that hasn't been resolved yet - Places API (New) splits
/// Autocomplete (text + [placeId], no coordinates) from Place Details
/// (coordinates), so [AddressAutocompleteField] fills [location] in on
/// selection rather than up front. Nominatim has no such split - its
/// results always carry [location] and never a [placeId].
class GeocodeResult {
  const GeocodeResult({required this.displayName, this.location, this.placeId})
      : assert(
          location != null || placeId != null,
          'a result needs a location, or a placeId to resolve one from',
        );

  final String displayName;
  final LatLng? location;
  final String? placeId;
}

/// Turns a typed address/place name into candidate coordinates, using
/// OpenStreetMap's free Nominatim service - same reasoning as
/// `reverse_geocode.dart`: no API key, no billing, consistent with the
/// rest of this self-hostable app. The map itself still renders via
/// Google Maps; this only powers the search box that jumps the map to
/// what someone typed. Returns an empty list on any failure or empty
/// query, never throws.
///
/// [sessionToken] is accepted but unused - it only matters for Google's
/// billing model (see `searchAddressGoogle`) - purely so both functions
/// share one signature and [AddressAutocompleteField] can swap between
/// them without a wrapper closure.
Future<List<GeocodeResult>> searchAddress(
  String query, {
  String? sessionToken,
}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': trimmed,
      'limit': '5',
    });
    final response = await http
        .get(
          uri,
          headers: {'User-Agent': '$kAppName courier app (self-hosted)'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as List;
    return data
        .map((row) {
          final map = row as Map<String, dynamic>;
          final lat = double.tryParse(map['lat'] as String? ?? '');
          final lon = double.tryParse(map['lon'] as String? ?? '');
          final displayName = map['display_name'] as String?;
          if (lat == null || lon == null || displayName == null) return null;
          return GeocodeResult(
            displayName: displayName,
            location: LatLng(lat, lon),
          );
        })
        .whereType<GeocodeResult>()
        .toList();
  } catch (_) {
    return const [];
  }
}
