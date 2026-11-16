import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Bằng chứng native được lưu trong dự án Flutter, tách khỏi reference React.
Future<void> main() async {
  final directory = Directory('docs/evidence/phase2');
  await directory.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data != null) {
        await File('${directory.path}/flutter-${data['captureWidth']}.json')
            .writeAsString(jsonEncode(data['metrics']));
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
  );
}
