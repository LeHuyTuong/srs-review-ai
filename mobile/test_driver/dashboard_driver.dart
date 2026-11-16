import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Lưu ảnh từ emulator về dự án; không ghi file ra nguồn React.
Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      final file = File(
        'docs/evidence/phase1/flutter-${data['captureWidth']}.json',
      );
      await file.writeAsString(jsonEncode(data['metrics']));
    },
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory('docs/evidence/phase1');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      if (args != null) {
        await File('${directory.path}/$name.json')
            .writeAsString(jsonEncode(args));
      }
      return bytes.isNotEmpty;
    },
  );
}
