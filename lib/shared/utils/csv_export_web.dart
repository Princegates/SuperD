// dart:html is legacy but still the simplest way to trigger a browser
// download without adding a package:web/js_interop dependency just for
// this one file - and it's never imported outside this web-only,
// conditionally-compiled implementation (see csv_export.dart), so the
// usual "don't use web libraries in a cross-platform Flutter app" lint
// doesn't actually apply here.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

/// Triggers a real browser download via a Blob + a synthetic anchor click
/// - see `csv_export.dart`. `dart:html` is part of the Flutter web SDK
/// itself, not a pubspec dependency, and this file is only ever compiled
/// in on web (see the conditional import there).
bool downloadCsv({required String filename, required String csvContent}) {
  final bytes = utf8.encode(csvContent);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
