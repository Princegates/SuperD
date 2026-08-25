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

Future<void> launchPhoneCall(String phoneNumber) async {
  await launchUrl(Uri.parse('tel:$phoneNumber'));
}
