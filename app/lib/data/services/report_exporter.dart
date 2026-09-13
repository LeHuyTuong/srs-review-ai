/// Writes a text report to a file the user chooses, or shares it.
///
/// `file_picker`'s saveFile writes the bytes itself and works on every target
/// this app ships on — including web, where it triggers a browser download —
/// so the save path needs no `dart:io` and no platform channels.
///
/// The share path is different: the OS share sheet is native-only, and while
/// `dart:io` compiles for web it throws `UnsupportedError` at the first call.
/// [share] therefore guards the platform itself instead of letting a stray
/// caller meet the cryptic error.
///
/// Before this the only way to get a report out of the app was the clipboard.
/// A review you cannot attach to a submission is not really an export.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform/app_platform.dart';

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

  /// Opens the OS share sheet with the report attached as a file.
  ///
  /// Goal §4 Output row: "ledger.md + JSON + share sheet". Writing a file is
  /// not the same as handing it to a supervisor — on mobile the native flow
  /// is AirDrop / Drive / Mail, and this is the only entry into it.
  ///
  /// Writes a temp file (the share sheet needs a real path on mobile
  /// targets) and returns the temp path so the caller can surface it. All
  /// ShareResultStatus outcomes (success/dismiss/unavailable) mean "the
  /// sheet opened and the user did whatever they did" — the app has no
  /// business second-guessing the user's choice, so the path is returned
  /// regardless.
  Future<String> share({
    required String fileName,
    required String contents,
  }) async {
    if (AppPlatform.isWeb) {
      // The UI hides the button in the browser; this guard is for callers
      // that reach the service directly — an explicit, explainable failure
      // beats a runtime UnsupportedError from dart:io.
      throw UnsupportedError(
        'The share sheet is not available in the browser; save the report '
        'as a file instead.',
      );
    }
    final dir = await Directory.systemTemp.createTemp('srs-review');
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(contents, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], title: fileName),
    );
    return file.path;
  }
}
