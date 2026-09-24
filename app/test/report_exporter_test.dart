/// The report writer's plugin seam.
///
/// `file_picker`'s save dialog and the OS share sheet are platform channels:
/// they exist inside a real host and nowhere else. Both are injected
/// ([SaveFileDialog], [ShareSheet]) so this file can prove the bytes, the
/// MIME type and the destination survive the trip without a channel — which is
/// the whole reason the seam exists, and what the native-plugin guardrail in
/// tools/check_guardrails.py refuses to let anyone remove.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/report_exporter.dart';

void main() {
  test('save hands the file name, MIME type and bytes to the dialog', () async {
    final calls = <String, Object?>{};
    final exporter = ReportExporter(
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            required String dialogTitle,
          }) async {
            calls['fileName'] = fileName;
            calls['mimeType'] = mimeType;
            calls['dialogTitle'] = dialogTitle;
            calls['contents'] = utf8.decode(bytes);
            return Uri.parse('file:///tmp/$fileName');
          },
    );

    final destination = await exporter.save(
      fileName: 'report.md',
      contents: '# SRS review',
    );

    expect(destination, 'file:///tmp/report.md');
    expect(calls['fileName'], 'report.md');
    expect(calls['mimeType'], 'text/markdown');
    expect(calls['dialogTitle'], 'Save review report');
    expect(calls['contents'], '# SRS review');
  });

  test(
    'the structured twins reach the dialog with their own MIME type',
    () async {
      String? seenMime;
      final exporter = ReportExporter(
        saveFile:
            ({
              required String fileName,
              required Uint8List bytes,
              required String mimeType,
              required String dialogTitle,
            }) async {
              seenMime = mimeType;
              return Uri.parse('file:///tmp/$fileName');
            },
      );

      await exporter.save(
        fileName: 'report.json',
        contents: '{}',
        mimeType: 'application/json',
      );

      expect(seenMime, 'application/json');
    },
  );

  test('a cancelled save returns null instead of a destination', () async {
    final exporter = ReportExporter(
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            required String dialogTitle,
          }) async => null,
    );

    expect(
      await exporter.save(fileName: 'report.md', contents: '# SRS'),
      isNull,
      reason: 'the user closing the dialog is not an export',
    );
  });

  test('share writes the report and hands its path to the sheet', () async {
    final handed = <String, String>{};
    final exporter = ReportExporter(
      shareSheet: ({required String path, required String title}) async {
        handed['path'] = path;
        handed['title'] = title;
      },
    );

    final path = await exporter.share(
      fileName: 'report.md',
      contents: '# SRS review',
    );
    addTearDown(() {
      final dir = File(path).parent;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    expect(handed['title'], 'report.md');
    expect(
      handed['path'],
      path,
      reason: 'the sheet must receive the file that was actually written',
    );
    expect(File(path).readAsStringSync(), '# SRS review');
  });
}
