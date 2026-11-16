/// The four horizontal overflows the 2026-09-26 surface audit found ONLY at
/// 390 px, pinned as geometry rather than as "no RenderFlex overflow".
///
/// Why geometry: a starved `Expanded` renders no overflow error at all. The
/// audit's own sixth find (same commit) is the proof — `criteria_manager`'s
/// action row left the primary button 28.2 px at 390, narrower than `WButton`'s
/// own 30 px of horizontal padding, so "Thêm tiêu chí" ellipsized to nothing and
/// the pill was empty. Zero overflow errors, one broken button. So every
/// assertion here measures a SIZE (`getSize`/`getRect`) and the error drain is a
/// second gate, not the only one.
///
/// The numbers these assertions pin, measured with the pre-fix code restored and
/// then without it (`docs/evidence/surface-audit-2026-09-26.md` §3.1, §3.1.1,
/// §4.1):
///
/// | site                        | before @390        | after @390        |
/// |-----------------------------|--------------------|-------------------|
/// | criteria_mgr primary button | 28.2 px, label 0.0 | 224.3 px          |
/// | criterion editor dropdowns  | 2 × 88 px overflow | 2 × 326 px stacked|
/// | rubric editor action row    | 107 px overflow    | wraps             |
/// | report count chips          | 15 px overflow     | wraps at chip 6   |
///
/// `canEdit` of both editors is `reviewApiProvider is ApiService`
/// (`core/providers.dart`), so [MockReviewApi] leaves them disabled and the
/// criterion editor — the only place with the two dropdowns — is never built.
/// [_EditApi] is a real [ApiService] with its network methods answered locally
/// for exactly that reason; measuring the disabled screen measures nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/core/theme/app_tokens.dart';
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';
import 'package:srs_review_ai/deterministic_checks/models/ai_criterion.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

/// The phone the audit measured at, and the wide control that must not regress.
const _phone = Size(390, 844);
const _wide = Size(1200, 900);

/// The live scale (`server/app/config/rubric.json`), NOT
/// [RubricConfig.fallback]: the fallback carries no weights, so the editor
/// would not build the four weight fields and the weights section — the one
/// with the trailing badge — would not render at all.
const _liveRubric = RubricConfig(
  version: 'v3-test',
  ucCountMin: 20,
  ucCountMax: null,
  ucMinTransactions: 3,
  ucMaxTransactions: 7,
  passMark: 5,
  minPerPart: 2,
  warnScore: 6,
  weights: {
    'clear': 0.25,
    'testable': 0.4,
    'complete': 0.2,
    'consistent': 0.15,
  },
);

/// A real [ApiService] so `canEdit` is true. Only the calls the two editors make
/// are answered; anything else reaching the network is a bug in this test, and
/// `127.0.0.1:9` (discard) fails it loudly instead of hanging.
class _EditApi extends ApiService {
  _EditApi() : super(baseUrl: 'http://127.0.0.1:9');

  @override
  Future<bool> isProxyUp() async => true;

  @override
  Future<RubricConfig> fetchRubric() async => _liveRubric;

  @override
  Future<List<AiCriterion>> fetchCriteria() async => const [];

  @override
  Future<List<AiCriterion>> resetCriteria() async => const [];
}

/// `takeException()` hands back ONE error and leaves the rest queued, so a
/// single call reports the first and hides the second — the trap AGENTS.md
/// names. Drain the whole queue.
List<Object> _drain(WidgetTester tester) {
  final out = <Object>[];
  while (true) {
    final error = tester.takeException();
    if (error == null) break;
    out.add(error as Object);
  }
  return out;
}

String _describe(List<Object> errors) =>
    errors.map((e) => e.toString().split('\n').first).join(' || ');

/// Closes every open full-screen surface.
///
/// `find.byTooltip('Đóng')` is ambiguous while two are stacked, and the close
/// button is the only way out through the UI, so pop until none is left.
Future<void> _closeSurfaces(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    final close = find.byTooltip('Đóng');
    if (close.evaluate().isEmpty) return;
    await tester.tap(close.last);
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 400,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  ProviderContainer container,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The router must be the mounted one: navigating a second instance's `go()`
  // is a silent no-op and measuring what is still on screen is not a
  // measurement (this harness itself lost a round to that).
  final router = buildRouter();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _pumpWhile(
    tester,
    () => find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
  );
  return router;
}

void main() {
  for (final size in const [_phone, _wide]) {
    testWidgets('syllabus editors hold their content at ${size.width}px', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
          reviewApiProvider.overrideWithValue(_EditApi()),
        ],
      );
      addTearDown(container.dispose);
      final router = await _pumpApp(tester, container, size);

      await container.read(workspaceViewModelProvider.notifier).loadDemo();
      await tester.pumpAndSettle();
      // The extraction toast overlays the lower screen for ~4.5s.
      await tester.pump(const Duration(seconds: 5));

      router.go(AppRoutes.syllabus);
      await tester.pumpAndSettle();
      final contentRight = size.width - AppSpacing.xxxl;

      // ---- criteria manager: the starved-Expanded button -------------------
      await tester.tap(find.text('Quản lý tiêu chí AI'));
      await tester.pumpAndSettle();
      final primary = find.widgetWithText(FilledButton, 'Thêm tiêu chí');
      final primaryWidth = tester.getSize(primary).width;
      final primaryLabel = tester.getSize(find.text('Thêm tiêu chí')).width;
      expect(
        primaryWidth,
        // 30 = WButton's own horizontal padding; below that the label can
        // never be shown whatever the font does.
        greaterThanOrEqualTo(primaryLabel + 30),
        reason:
            'the primary button is starved: $primaryWidth px for a '
            '$primaryLabel px label (28.2 in the audit before the fix)',
      );
      final managerErrors = _drain(tester);
      expect(managerErrors, isEmpty, reason: _describe(managerErrors));

      // ---- criterion editor: the two dropdowns ----------------------------
      await tester.tap(find.text('Thêm tiêu chí'));
      await tester.pumpAndSettle();
      expect(find.text('Áp dụng cho'), findsOneWidget);
      final scope = find.byType(DropdownButtonFormField<CriterionScope>);
      final severity = find.byType(DropdownButtonFormField<CriterionSeverity>);
      final scopeRect = tester.getRect(scope);
      final severityRect = tester.getRect(severity);
      // Equal, full-width and stacked: the fix is a Column, and a revert to the
      // Row of two Expanded fields puts them side by side at half the width.
      expect(scopeRect.width, severityRect.width);
      expect(scopeRect.width, greaterThan(200));
      expect(
        severityRect.top,
        greaterThanOrEqualTo(scopeRect.bottom),
        reason: 'the two dropdowns share a row again',
      );
      final editorErrors = _drain(tester);
      expect(editorErrors, isEmpty, reason: _describe(editorErrors));

      await _closeSurfaces(tester);

      // ---- rubric editor: the title+badge row and the action row ----------
      await tester.tap(find.text('Sửa thang điểm'));
      await tester.pumpAndSettle();
      expect(find.text('Chuẩn syllabus & thang điểm'), findsOneWidget);
      expect(find.text('Tổng 1.00'), findsOneWidget);
      for (final label in ['Tổng 1.00', 'Khôi phục mặc định', 'Đóng', 'Lưu']) {
        final rect = tester.getRect(find.text(label));
        expect(
          rect.right,
          lessThanOrEqualTo(contentRight),
          reason: '"$label" is laid out past the content edge ($rect)',
        );
      }
      final rubricErrors = _drain(tester);
      expect(rubricErrors, isEmpty, reason: _describe(rubricErrors));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('report count row fits ${size.width}px', (tester) async {
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
          reviewApiProvider.overrideWithValue(
            const MockReviewApi(latency: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = await _pumpApp(tester, container, size);

      // A finished run, not the empty page: on an unrun report the chips are
      // all "0", narrow, and the row cannot overflow — a green that proves
      // nothing.
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();
      for (final unit
          in container
              .read(workspaceViewModelProvider)
              .units
              .where((u) => u.selected)
              .skip(40)) {
        vm.setUnitSelected(unit.key, false);
      }
      await vm.runReview();
      await _pumpWhile(
        tester,
        () => !container.read(workspaceViewModelProvider).hasResult,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      router.go(AppRoutes.report);
      await tester.pumpAndSettle();
      expect(find.text('Đánh giá tổng quan'), findsOneWidget);

      final chips = find.byWidgetPredicate(
        (w) => w is Wrap && w.children.length == 6,
      );
      expect(
        chips,
        findsOneWidget,
        reason:
            'the six count chips are not a Wrap (a Row overflowed 15 px '
            'at 390 before the fix)',
      );
      // Identifies which six-child Wrap this is, rather than trusting the count.
      expect(
        find.descendant(of: chips, matching: find.text('Người')),
        findsOneWidget,
      );
      final rowRect = tester.getRect(chips);
      final texts = find.descendant(of: chips, matching: find.byType(Text));
      for (var i = 0; i < texts.evaluate().length; i++) {
        final rect = tester.getRect(texts.at(i));
        expect(
          rect.right,
          lessThanOrEqualTo(rowRect.right + 0.5),
          reason: 'a count chip spilled out of its row: $rect',
        );
      }
      final reportErrors = _drain(tester);
      expect(reportErrors, isEmpty, reason: _describe(reportErrors));
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
