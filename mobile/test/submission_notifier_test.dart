import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_mobile/features/student/data/services/submission_notifier.dart';

// Tách khỏi file widget test: TestWidgetsFlutterBinding thay HttpClient bằng
// bản giả luôn trả 400, nên test gọi HTTP thật phải ở file không có testWidgets.
void main() {
  test('notifier posts the submission id with the Firebase token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <(String, String?, Object?)>[];
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      seen.add((
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader),
        jsonDecode(body),
      ));
      request.response.statusCode = 200;
      await request.response.close();
    });

    final notifier = HttpSubmissionNotifier(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      idToken: () async => 'tok',
    );
    expect(await notifier.notifyTeachers('s1'), isTrue);
    expect(seen.single.$1, '/notifications/submission');
    expect(seen.single.$2, 'Bearer tok');
    expect(seen.single.$3, {'submissionId': 's1'});
  });

  test('notifier reports failure instead of throwing', () async {
    final notifier = HttpSubmissionNotifier(
      // Nothing listens on port 9 on loopback.
      baseUri: Uri.parse('http://127.0.0.1:9'),
      idToken: () async => 'tok',
    );
    expect(await notifier.notifyTeachers('s1'), isFalse);
  });
}
