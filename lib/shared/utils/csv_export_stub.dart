/// No-op fallback for any platform without `dart:html` (Android, iOS,
/// desktop) - see `csv_export.dart`.
bool downloadCsv({required String filename, required String csvContent}) =>
    false;
