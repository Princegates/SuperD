import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the device's native maps app for turn-by-turn navigation to a point.
/// Uses Apple Maps on iOS and Google Maps (or any geo: handler) on Android —
/// no API key required, this is just a deep link.
Future<void> launchNavigation({
  required double lat,
  required double lng,
}) async {
  final uri = (!kIsWeb && Platform.isIOS)
      ? Uri.parse('https://maps.apple.com/?daddr=$lat,$lng')
      : Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
        );

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens the device's native maps app centered on a point, as a plain pin -
/// not turn-by-turn directions (see [launchNavigation]). For a customer
/// checking where their rider currently is, they're not the one driving
/// there, so a route from their own location doesn't make sense; this just
/// shows the point. Google's `maps/search` URL works identically on
/// Android, iOS, and web (opens the app if installed, the browser
/// otherwise), so there's no platform branch needed here.
Future<void> launchMapView({required double lat, required double lng}) async {
  await launchUrl(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> launchPhoneCall(String phoneNumber) async {
  await launchUrl(Uri.parse('tel:$phoneNumber'));
}
