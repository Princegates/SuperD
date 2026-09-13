import 'package:flutter/material.dart';

import '../utils/csv_export.dart';

/// A "download this as CSV" button that behaves the same everywhere.
///
/// The download itself is web-only (see [downloadCsv]) because the
/// Console is a back-office surface. On anything else the attempt
/// silently returns false, so this says so out loud rather than leaving
/// someone tapping a button that appears to do nothing.
///
/// [csv] is called only when pressed. Some of these exports run over
/// every delivery ever made, and that is not work to do on every rebuild
/// of a screen nobody is exporting from.
class CsvExportButton extends StatelessWidget {
  const CsvExportButton({
    super.key,
    required this.filename,
    required this.csv,
    this.label = 'Export CSV',
    this.enabled = true,
  });

  /// Name the file is offered under, e.g. `commission.csv`.
  final String filename;

  /// Produces the document. Deferred until the press.
  ///
  /// Named `csv` rather than the more obvious `build` because a field of
  /// that name collides with StatelessWidget.build.
  final String Function() csv;

  final String label;

  /// False greys the button out - there is nothing to export yet.
  final bool enabled;

  void _export(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final downloaded = downloadCsv(filename: filename, csvContent: csv());
    if (!downloaded) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('CSV export is only available from the web dashboard.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? () => _export(context) : null,
      icon: const Icon(Icons.download_outlined, size: 18),
      label: Text(label),
    );
  }
}
