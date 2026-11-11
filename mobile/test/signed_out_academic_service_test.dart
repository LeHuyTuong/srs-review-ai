import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Đăng xuất làm provider dựng lại service cho phiên rỗng trước khi màn cũ
  // kịp gỡ; service đó từng mở listener Firestore và ra hàng loạt
  // permission-denied (đo trên web 11/11/2026).
  test(
    'phiên rỗng: service không chạm Firestore, load báo phiên hết hạn',
    () async {
      final c = ProviderContainer(
        overrides: [
          firebaseInitializedProvider.overrideWithValue(true),
          firestoreProvider.overrideWith(
            (ref) =>
                throw StateError('không được đọc Firestore khi chưa đăng nhập'),
          ),
        ],
      );
      addTearDown(c.dispose);

      final service = c.read(firestoreAcademicServiceProvider);
      await expectLater(
        service.load(),
        throwsA(
          isA<AcademicFailure>().having(
            (e) => e.code,
            'code',
            AcademicErrorCode.sessionExpired,
          ),
        ),
      );
    },
  );
}
