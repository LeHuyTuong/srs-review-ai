import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final phase = Platform.environment['BEHAVIOR_CAPTURE_PHASE'] ?? 'after';
  final directory = Directory('.local/behavior-refactor/android-$phase');
  await directory.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      final summary = Map<String, dynamic>.from(data)..remove('screenshots');
      await File('${directory.path}/results.json')
          .writeAsString(jsonEncode(summary));
    },
    onScreenshot: (name, bytes, [args]) async {
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
  );
}
