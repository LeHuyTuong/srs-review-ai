import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/views/login_screen.dart';
import 'package:srs_review_ai_mobile/main.dart' as app;
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Firebase startup reaches login without native plugin errors', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(Firebase.app().options.projectId, 'srs-ai-prm');
    expect(find.byType(LoginScreen), findsOneWidget);
    if (kIsWeb) {
      final context = tester.element(find.byType(LoginScreen));
      final service = ProviderScope.containerOf(context)
          .read(crashlyticsServiceProvider);
      expect(service, isNot(isA<FirebaseCrashlyticsService>()));
      await service.log('startup smoke test');
      await service.setUser(null);
    }
    final exceptions = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      exceptions.add(exception!);
    }
    expect(exceptions, isEmpty);
  });
}
