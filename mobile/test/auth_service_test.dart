import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/services/auth_service.dart';

void main() {
  setUp(AuthService.resetGoogleInitialization);

  group('resolveGoogleSignInInit', () {
    test('web dùng clientId và không truyền serverClientId', () {
      final init = resolveGoogleSignInInit(
        isWeb: true,
        webClientId: 'web-client',
      );
      expect(init.clientId, 'web-client');
      expect(init.serverClientId, isNull);
    });

    test('native dùng serverClientId và không truyền clientId', () {
      final init = resolveGoogleSignInInit(isWeb: false);
      expect(init.clientId, isNull);
      expect(init.serverClientId, isNotEmpty);
    });

    test('web thiếu client id thì báo lỗi nêu đúng lệnh cần chạy', () {
      expect(
        () => resolveGoogleSignInInit(isWeb: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('flutter_env.py mobile prepare'),
          ),
        ),
      );
    });
  });

  test('Google Sign-In chỉ khởi tạo một lần cho cả vòng đời app', () async {
    final calls = <GoogleSignInInit>[];
    final service = AuthService(
      googleInitializer: ({clientId, serverClientId}) async {
        calls.add(
          GoogleSignInInit(clientId: clientId, serverClientId: serverClientId),
        );
      },
    );

    await service.ensureGoogleInitialized();
    await service.ensureGoogleInitialized();

    expect(calls, hasLength(1));
  });

  test('khởi tạo lỗi thì lần sau không gọi init() lần nữa', () async {
    var calls = 0;
    final service = AuthService(
      googleInitializer: ({clientId, serverClientId}) async {
        calls++;
        throw StateError('init failed');
      },
    );

    await expectLater(service.ensureGoogleInitialized(), throwsStateError);
    await expectLater(service.ensureGoogleInitialized(), throwsStateError);

    expect(calls, 1);
  });
}
