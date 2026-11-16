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

/// Opens the platform save dialog and writes [bytes], returning where the
/// platform put the file (null = the user cancelled).
///
/// Injected rather than called straight through to `file_picker` so the plugin
/// stays replaceable: the channel exists only inside a real host, so without
/// this seam the one write path a report has could not be exercised anywhere
/// but on a device. The production default is
/// [filePickerSaveDialog] below.
typedef SaveFileDialog =
    Future<Uri?> Function({
      required String fileName,
      required Uint8List bytes,
      required String mimeType,
      required String dialogTitle,
    });

/// Hands the written file to the OS share sheet. Injected for the same reason
/// as [SaveFileDialog]: the share sheet is native-only, and a test has to be
/// able to prove the file reached it without a channel.
typedef ShareSheet =
    Future<void> Function({required String path, required String title});

class ReportExporter {
  const ReportExporter({
    SaveFileDialog saveFile = filePickerSaveDialog,
    ShareSheet shareSheet = sharePlusShareSheet,
  }) : // Named initializing formals cannot target a private field, so these
       // assignments have to stay explicit (same as DocumentRepository).
       // ignore: prefer_initializing_formals
       _saveFile = saveFile,
       // ignore: prefer_initializing_formals
       _shareSheet = shareSheet;

  final SaveFileDialog _saveFile;
  final ShareSheet _shareSheet;

  /// Opens the platform save dialog and writes [contents].
  ///
  /// Returns the destination as the platform reported it, or null when the
  /// user cancelled. A thrown error is a real failure the caller should show.
  Future<String?> save({
    required String fileName,
    required String contents,
    // The export family grew beyond markdown: the JSON and HTML twins need
    // their own MIME so the platform dialog suggests the right type.
    String mimeType = 'text/markdown',
  }) => saveBytes(
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode(contents)),
    mimeType: mimeType,
  );

  /// The binary leg of the same door. A .docx is bytes, not text: pushing it
  /// through [save] would utf8-encode a ZIP container and hand Word a file it
  /// cannot open, which is why this exists instead of a second save dialog.
  ///
  /// Returns the destination as the platform reported it, or null when the user
  /// cancelled. A thrown error is a real failure the caller should show.
  Future<String?> saveBytes({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final uri = await _saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
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
    await _shareSheet(path: file.path, title: fileName);
    return file.path;
  }
}

/// The production save dialog: `file_picker` writes the bytes itself, on every
/// target this app ships on.
Future<Uri?> filePickerSaveDialog({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  required String dialogTitle,
}) => FilePicker.saveFile(
  fileName: fileName,
  bytes: bytes,
  mimeType: mimeType,
  dialogTitle: dialogTitle,
);

/// The production share sheet.
Future<void> sharePlusShareSheet({
  required String path,
  required String title,
}) => SharePlus.instance.share(ShareParams(files: [XFile(path)], title: title));
