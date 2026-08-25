import 'dart:convert';

import 'package:http/http.dart' as http;

/// Turns coordinates into a human-readable address using OpenStreetMap's
/// free Nominatim service (no API key). Returns null on any failure so
/// callers can fall back to showing the raw coordinates instead.
Future<String?> reverseGeocode(double lat, double lng) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': lat.toString(),
      'lon': lng.toString(),
    });
    final response = await http
        .get(uri, headers: {'User-Agent': 'SuperD courier app (self-hosted)'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final displayName = data['display_name'] as String?;
    return (displayName == null || displayName.trim().isEmpty)
        ? null
        : displayName;
  } catch (_) {
    return null;
  }
}
