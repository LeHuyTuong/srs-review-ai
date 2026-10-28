import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('docs/evidence/phase4');
  await directory.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data != null) {
        final summary = <String, dynamic>{...data}..remove('screenshots');
        summary['screenshots'] = [
          for (final screenshot in data['screenshots'] as List? ?? [])
            screenshot['screenshotName'],
        ];
        await File('${directory.path}/android-${data['captureWidth']}.json')
            .writeAsString(jsonEncode(summary));
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
  );
}
