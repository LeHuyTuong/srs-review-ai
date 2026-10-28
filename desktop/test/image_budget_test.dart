import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/diagram_audit/services/image_budget.dart';

/// [ImageBudget] decisions, not bookkeeping.
///
/// The behavior that matters in a 60-unit run: same-page requirements share
/// one reservation, the ceiling stops the run rather than the request, and a
/// spent budget degrades to text-only review instead of throwing.
void main() {
  group('reservations dedupe by page', () {
    test('reserving the same page twice spends one slot', () {
      final budget = ImageBudget(maxPages: 2)..tryReserve(3);
      expect(budget.tryReserve(3), isTrue);
      expect(budget.used, 1);
    });

    test('a reserved page keeps answering canAttach after exhaustion', () {
      final budget = ImageBudget(maxPages: 1)..tryReserve(5);
      expect(budget.isExhausted, isTrue);
      expect(budget.canAttach(5), isTrue, reason: 'already-paid page');
      expect(budget.canAttach(6), isFalse, reason: 'budget spent');
    });
  });

  group('exhaustion degrades, never throws', () {
    test('tryReserve on a spent budget returns false and reserves nothing', () {
      final budget = ImageBudget(maxPages: 1)
        ..tryReserve(1)
        ..tryReserve(2);
      expect(budget.used, 1);
      expect(budget.canAttach(2), isFalse);
    });

    test('a zero-page budget rejects every page but not the free path', () {
      final budget = ImageBudget(maxPages: 0);
      expect(budget.tryReserve(1), isFalse);
      expect(budget.canAttach(null), isTrue);
    });
  });

  test('null page index is always free — nothing to guard', () {
    final budget = ImageBudget(maxPages: 0);
    expect(budget.canAttach(null), isTrue);
  });

  test('distinct pages are counted, not calls', () {
    final budget = ImageBudget(maxPages: 3);
    for (final page in [7, 8, 7, 9, 7]) {
      budget.tryReserve(page);
    }
    expect(budget.used, 3);
    expect(budget.isExhausted, isTrue);
  });

  test('a negative maxPages is rejected at construction', () {
    expect(() => ImageBudget(maxPages: -1), throwsArgumentError);
  });

  test('a run without configuration still gets a ceiling, not a free pass', () {
    final budget = ImageBudget();
    expect(budget.maxPages, 12, reason: 'roadmap M4 experimental default');
    for (var page = 0; page < 12; page++) {
      expect(budget.tryReserve(page), isTrue);
    }
    expect(
      budget.tryReserve(12),
      isFalse,
      reason: 'degrade to text-only, never balloon',
    );
  });
}
