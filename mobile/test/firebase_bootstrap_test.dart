import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/services/crashlytics_support.dart';
import 'package:srs_review_ai_mobile/core/services/firebase_bootstrap.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/views/crashlytics_test_tile.dart';
import 'package:srs_review_ai_mobile/firebase_options.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final flutterHandler = FlutterError.onError;
    final platformHandler = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutterHandler;
      PlatformDispatcher.instance.onError = platformHandler;
      debugDefaultTargetPlatformOverride = null;
    });
  });

  for (final platform in TargetPlatform.values) {
    test('bootstrap respects $platform and the web runtime', () async {
      debugDefaultTargetPlatformOverride = platform;
      final calls = <String>[];
      final fake = _FakeCrashlytics(calls);
      final supported =
          !kIsWeb &&
          {
            TargetPlatform.android,
            TargetPlatform.iOS,
            TargetPlatform.macOS,
          }.contains(platform);
      final originalFlutterHandler = FlutterError.onError;
      final originalPlatformHandler = PlatformDispatcher.instance.onError;

      await bootstrapFirebase(
        initializeFirebase: () async => calls.add('initialize'),
        crashlyticsFactory: () {
          calls.add('crashlytics');
          return fake;
        },
        registerBackgroundMessaging: () => calls.add('background'),
        forceCrashReporting: false,
      );

      expect(calls, [
        'initialize',
        if (supported) ...['crashlytics', 'collection:false'],
        if (!kIsWeb) 'background',
      ]);
      expect(supportsCrashlytics, supported);
      if (supported) {
        final error = StateError('probe');
        final stack = StackTrace.current;
        FlutterError.onError!(FlutterErrorDetails(exception: error));
        expect(PlatformDispatcher.instance.onError!(error, stack), isTrue);
        expect(fake.flutterError, same(error));
        expect(fake.asyncError, same(error));
        expect(fake.asyncStack, same(stack));
        expect(fake.fatal, isTrue);
      } else {
        expect(FlutterError.onError, same(originalFlutterHandler));
        expect(
          PlatformDispatcher.instance.onError,
          same(originalPlatformHandler),
        );
      }
    });
  }

  test('debug reporting can be explicitly enabled on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    await bootstrapFirebase(
      initializeFirebase: () async {},
      crashlyticsFactory: () => _FakeCrashlytics(calls),
      registerBackgroundMessaging: () {},
      forceCrashReporting: true,
    );
    expect(calls, kIsWeb ? isEmpty : ['collection:true']);
  });

  test(
    'Firebase initialization failure is preserved before SDK setup',
    () async {
      final error = StateError('initialization failed');
      await expectLater(
        bootstrapFirebase(
          initializeFirebase: () async => throw error,
          crashlyticsFactory: () =>
              throw StateError('must not access Crashlytics'),
          registerBackgroundMessaging: () =>
              fail('must not register messaging'),
        ),
        throwsA(same(error)),
      );
    },
  );

  test('provider is safe without Firebase, including crash requests', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(crashlyticsServiceProvider);
    expect(service, isNot(isA<FirebaseCrashlyticsService>()));
    await service.setUser('probe');
    await service.setCustomKey('probe', true);
    await service.log('probe');
    await service.logError(StateError('probe'), StackTrace.current);
    await service.triggerTestCrash();
  });

  test('platform Firebase options select the same project', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = kIsWeb
        ? DefaultFirebaseOptions.web
        : DefaultFirebaseOptions.android;
    expect(options.projectId, 'srs-ai-prm');
    expect(options.appId, contains(kIsWeb ? ':web:' : ':android:'));
    expect(
      DefaultFirebaseOptions.web.projectId,
      DefaultFirebaseOptions.android.projectId,
    );
    if (options.apiKey.isEmpty) {
      expect(() => DefaultFirebaseOptions.currentPlatform, throwsStateError);
    } else {
      expect(DefaultFirebaseOptions.currentPlatform, same(options));
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('crash test tile visibility on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CrashlyticsTestTile())),
        ),
      );
      expect(
        find.text('Kiểm thử Crashlytics'),
        !kIsWeb && platform == TargetPlatform.android
            ? findsOneWidget
            : findsNothing,
      );
      final exceptions = <Object>[];
      Object? exception;
      while ((exception = tester.takeException()) != null) {
        exceptions.add(exception!);
      }
      expect(exceptions, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

class _FakeCrashlytics implements FirebaseCrashlytics {
  _FakeCrashlytics(this.calls);

  final List<String> calls;
  Object? flutterError;
  Object? asyncError;
  StackTrace? asyncStack;
  bool? fatal;

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    calls.add('collection:$enabled');
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    flutterError = details.exception;
  }

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool? printDetails,
    bool fatal = false,
  }) async {
    asyncError = exception;
    asyncStack = stack;
    this.fatal = fatal;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
