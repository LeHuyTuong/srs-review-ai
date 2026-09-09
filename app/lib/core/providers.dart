/// Dependency wiring. One place, so swapping the real proxy for the offline
/// mock is a single provider override.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/checks/rubric_config.dart';
import '../data/repositories/document_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/services/api_service.dart';
import '../data/services/mock_review_api.dart';
import '../data/services/review_api.dart';
import 'app_config.dart';

/// Runtime demo switch. Starts from the build-time flag but stays flippable on
/// stage: pulling the WiFi plug should not end the demo.
///
/// A [Notifier] rather than `StateProvider`, which Riverpod 3 moved to
/// `legacy.dart`.
class MockModeNotifier extends Notifier<bool> {
  @override
  bool build() => AppConfig.forceMockMode;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}

final mockModeProvider = NotifierProvider<MockModeNotifier, bool>(
  MockModeNotifier.new,
);

final reviewApiProvider = Provider<ReviewApi>((ref) {
  if (ref.watch(mockModeProvider)) return const MockReviewApi();
  return ApiService();
});

/// Rubric thresholds, straight from the proxy. Falls back to the committed
/// copy so the app still knows the syllabus numbers offline.
final rubricProvider = FutureProvider<RubricConfig>((ref) async {
  final api = ref.watch(reviewApiProvider);
  try {
    return await api.fetchRubric();
  } on Object {
    return RubricConfig.fallback;
  }
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  // AsyncValue.value is nullable in Riverpod 3 (there is no valueOrNull).
  return DocumentRepository(
    rubric: ref.watch(rubricProvider).value ?? RubricConfig.fallback,
  );
});

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(ref.watch(reviewApiProvider)),
);
