import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_detector.dart';
import 'package:srs_review_ai/data/services/image_budget.dart';
import 'package:srs_review_ai/data/services/page_image_selector.dart';

void main() {
  const diagramText =
      'The flow of UC04 is shown in the use case diagram below.';
  const plainText = 'The system shall reject an expired membership card.';

  PageImageSelector selectorWith(int maxPages) =>
      PageImageSelector(budget: ImageBudget(maxPages: maxPages));

  test('no intent skips without spending budget, even when a page exists', () {
    final selector = selectorWith(2);
    final plan = selector.planFor(
      requirementId: 'u1',
      text: plainText,
      pageIndex: 7,
      candidatePages: {7},
    );
    expect(plan.decision, PageImageDecision.skippedNoDiagramIntent);
    expect(plan.reason, 'no-diagram-intent');
    expect(selector.budget.used, 0, reason: 'gate order: intent first');
  });

  test('intent without a page reference has nothing to attach', () {
    final selector = selectorWith(2);
    final plan = selector.planFor(
      requirementId: 'u2',
      text: diagramText,
      pageIndex: null,
      candidatePages: {3, 4},
    );
    expect(plan.decision, PageImageDecision.skippedNoCandidatePage);
    expect(plan.reason, 'no-candidate-page');
    expect(selector.budget.used, 0);
  });

  test('intent on a page the parser did not flag is not a candidate', () {
    final selector = selectorWith(2);
    final plan = selector.planFor(
      requirementId: 'u3',
      text: diagramText,
      pageIndex: 9,
      candidatePages: {3, 4},
    );
    expect(plan.decision, PageImageDecision.skippedNoCandidatePage);
    expect(selector.budget.used, 0);
  });

  test('selection reserves the page and shares it across requirements', () {
    final selector = selectorWith(2);
    final first = selector.planFor(
      requirementId: 'u4',
      text: diagramText,
      pageIndex: 3,
      candidatePages: {3, 4},
    );
    final second = selector.planFor(
      requirementId: 'u5',
      text: 'See ERD-only figure on this page.',
      pageIndex: 3,
      candidatePages: {3, 4},
    );
    expect(first.decision, PageImageDecision.selected);
    expect(first.reason, isNull);
    expect(
      second.decision,
      PageImageDecision.selected,
      reason: 'same page shares one reservation',
    );
    expect(selector.budget.used, 1);
  });

  test('a spent budget defers a real candidate, reserving nothing more', () {
    final selector = selectorWith(1);
    selector.planFor(
      requirementId: 'u6',
      text: diagramText,
      pageIndex: 3,
      candidatePages: {3, 4},
    );
    final deferred = selector.planFor(
      requirementId: 'u7',
      text: 'The architecture is depicted in the diagram below.',
      pageIndex: 4,
      candidatePages: {3, 4},
    );
    expect(deferred.decision, PageImageDecision.deferredBudgetSpent);
    expect(deferred.reason, 'budget-spent');
    expect(selector.budget.used, 1);
  });

  test('intent gates before budget, so reasons never lie', () {
    final selector = selectorWith(0);
    final plan = selector.planFor(
      requirementId: 'u8',
      text: plainText,
      pageIndex: 3,
      candidatePages: {3},
    );
    expect(
      plan.decision,
      PageImageDecision.skippedNoDiagramIntent,
      reason: 'budget exhaustion must not mask a text-only requirement',
    );
    expect(selector.budget.used, 0);
  });

  test('a detector that stays silent keeps the plan text-only', () {
    final selector = PageImageSelector(
      detector: const DiagramDetector(),
      budget: ImageBudget(maxPages: 1),
    );
    final plan = selector.planFor(
      requirementId: 'u9',
      text: '   ',
      pageIndex: 3,
      candidatePages: {3},
    );
    expect(plan.decision, PageImageDecision.skippedNoDiagramIntent);
  });

  test(
    'selector with a permissive detector and a default budget still caps',
    () {
      final selector = PageImageSelector(budget: ImageBudget());
      var selected = 0;
      for (var page = 0; page < 20; page++) {
        final plan = selector.planFor(
          requirementId: 'u-page-$page',
          text: diagramText,
          pageIndex: page,
          candidatePages: {for (var i = 0; i < 20; i++) i},
        );
        if (plan.decision == PageImageDecision.selected) selected++;
      }
      expect(
        selected,
        selector.budget.maxPages,
        reason: 'roadmap default is 12; the rest defer, the run continues',
      );
    },
  );
}
