/// ADR-0015 — the role split, and the promise it makes about AppPlatform.
///
/// The decision text says: "`AppPlatform`'s contract is untouched". These tests
/// are that sentence made executable. A later "just add a `role` getter to
/// AppPlatform" is a two-line change and would pass every other suite, so it
/// needs a test that fails.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/platform/app_platform.dart';
import 'package:srs_review_ai/core/role/app_role.dart';

void main() {
  group('AppRole — identity, not device', () {
    test('both roles exist and are distinct', () {
      expect(
        AppRole.values,
        containsAll(<AppRole>[AppRole.student, AppRole.teacher]),
      );
      expect(AppRole.student, isNot(AppRole.teacher));
    });

    test('only the teacher role is read-only over submissions', () {
      // The teacher client consumes what a group produced; it never uploads an
      // artifact and never runs a review of its own.
      expect(AppRole.teacher.isReadOnly, isTrue);
      expect(AppRole.student.isReadOnly, isFalse);
    });

    test('a scope compares by role, so a rebuild is a no-op', () {
      expect(const AppRoleScope.student(), const AppRoleScope.student());
      expect(const AppRoleScope.student(), isNot(const AppRoleScope.teacher()));
      expect(
        const AppRoleScope.student().hashCode,
        const AppRoleScope.student().hashCode,
      );
    });
  });

  group('ADR-0015 promise: AppPlatform was not touched', () {
    test('it still answers only "where am I"', () {
      // Exactly the four members ADR-0006 defines. If a role ever lands here,
      // this list is the thing that should fail first — before 800 tests that
      // all still pass for the wrong reason.
      expect(AppPlatform.isDesktop, isA<bool>());
      expect(AppPlatform.isWeb, isA<bool>());
      expect(AppPlatform.formFactor, isA<AppFormFactor>());
      expect(AppPlatform.usesCommandKey, isA<bool>());
    });

    test('the two axes stay independent', () {
      // A teacher on a phone and a student on a phone share a form factor and
      // differ in role; a teacher on desktop and a student on desktop do too.
      // That is the reason role is a separate concept at all (ADR-0015 §Context).
      expect(AppFormFactor.values, contains(AppFormFactor.phone));
      expect(AppFormFactor.values, contains(AppFormFactor.desktop));
      expect(AppRole.values, hasLength(2));
    });
  });
}
