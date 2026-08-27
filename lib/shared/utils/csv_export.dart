import 'csv_export_stub.dart'
    if (dart.library.html) 'csv_export_web.dart'
    as impl;

/// Escapes a single CSV field - wraps it in quotes (doubling any internal
/// quotes) whenever it contains a comma, quote, or newline that would
/// otherwise break the format.
String csvField(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvRow(List<Object?> fields) => fields.map(csvField).join(',');

/// Builds a CSV document (header row + one row per item) from a list of
/// records, given the column headers and a function to turn one record
/// into its row's field values.
String buildCsv<T>({
  required List<String> headers,
  required List<T> rows,
  required List<Object?> Function(T) toRow,
}) {
  final buffer = StringBuffer(csvRow(headers))..write('\r\n');
  for (final row in rows) {
    buffer
      ..write(csvRow(toRow(row)))
      ..write('\r\n');
  }
  return buffer.toString();
}

/// Triggers a CSV file download named [filename] - web only (the Console
/// this is used from is a back-office, web-first surface - see README).
/// Returns false on any other platform, so a caller can show a fallback
/// message instead of silently doing nothing.
bool downloadCsv({required String filename, required String csvContent}) {
  return impl.downloadCsv(filename: filename, csvContent: csvContent);
}
