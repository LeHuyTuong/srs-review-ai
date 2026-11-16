import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Lưu ảnh gốc và metadata native để crop đúng system inset, không chỉnh nội dung ảnh.
Future<void> main() async {
  final directory = Directory('docs/evidence/phase3');
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
