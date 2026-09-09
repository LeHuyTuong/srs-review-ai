/// ViewModel for the review screen: owns the run, the progress and the results.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/repositories/review_repository.dart';

class ReviewState {
  const ReviewState({
    this.progress = const ReviewProgress(stage: ReviewStage.idle),
    this.run,
  });

  final ReviewProgress progress;
  final ReviewRun? run;

  bool get isRunning =>
      progress.stage == ReviewStage.parsing ||
      progress.stage == ReviewStage.reviewing ||
      progress.stage == ReviewStage.verifying;

  bool get hasResults => (run?.results.isNotEmpty) ?? false;
}

class ReviewViewModel extends Notifier<ReviewState> {
  StreamSubscription<ReviewProgress>? _subscription;

  @override
  ReviewState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const ReviewState();
  }

  Future<void> start(SrsDocument document) async {
    if (state.isRunning) return;
    final repository = ref.read(reviewRepositoryProvider);

    await _subscription?.cancel();
    state = const ReviewState(
      progress: ReviewProgress(stage: ReviewStage.parsing),
    );

    _subscription = repository
        .run(
          document,
          onComplete: (run) =>
              state = ReviewState(progress: state.progress, run: run),
        )
        .listen(
          (progress) => state = ReviewState(progress: progress, run: state.run),
        );
  }

  void cancel() => ref.read(reviewRepositoryProvider).cancel();

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    state = const ReviewState();
  }
}

final reviewViewModelProvider = NotifierProvider<ReviewViewModel, ReviewState>(
  ReviewViewModel.new,
);
