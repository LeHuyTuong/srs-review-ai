/// Writes a text report to a file the user chooses.
///
/// `file_picker`'s saveFile writes the bytes itself and works on every target
/// this app ships on — including web, where it triggers a browser download —
/// so this needs no `dart:io` and no platform channels.
///
/// Before this the only way to get a report out of the app was the clipboard.
/// A review you cannot attach to a submission is not really an export.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class ReportExporter {
  const ReportExporter();

  /// Opens the platform save dialog and writes [contents].
  ///
  /// Returns the destination as the platform reported it, or null when the
  /// user cancelled. A thrown error is a real failure the caller should show.
  Future<String?> save({
    required String fileName,
    required String contents,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(contents)),
      mimeType: 'text/markdown',
      dialogTitle: 'Save review report',
    );
    if (uri == null) return null;
    // The Uri scheme varies by platform (file / content / blob). Whatever it
    // is, it is the only handle the user gets to where the report went, so it
    // is what the confirmation message shows.
    return uri.toString();
  }
}
