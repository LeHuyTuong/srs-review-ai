import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/reference_checks.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/checks/syllabus_checks.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/services/api_service.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';

void main() {
  test('runtime messages preserve file names, counts and retry windows', () {
    const cases = {
      'Reading OTES English.docx (28.7 MB)…':
          'Đang đọc OTES English.docx (28.7 MB)…',
      'Parsing OTES.pdf…': 'Đang phân tích OTES.pdf…',
      '63 units extracted. All detected IDs have been preserved.':
          'Đã trích xuất 63 mục. Tất cả mã ID đều được giữ lại.',
      'Unable to read this document: This file is 31.5 MB. The limit is 30 MB.':
          'Không thể đọc tài liệu: Tệp có dung lượng 31.5 MB, vượt giới hạn 30 MB.',
      '40 units reviewed · 3 verified findings · 2 failed and were NOT reviewed · 23 left out by the 40-unit per-run cap · saved on this device':
          'Đã chấm 40 mục · 3 lỗi đã đối chiếu · 2 mục thất bại, chưa được chấm · 23 mục chưa chấm do giới hạn 40 mục/lượt · đã lưu trên thiết bị',
      'Review cancelled · 4 unit(s) reviewed and saved on this device.':
          'Đã hủy lượt chấm · Đã chấm và lưu 4 mục trên thiết bị.',
      // The missing-renderer honesty line, in both shapes the app shows it:
      // appended to the run summary, and standalone above the verdict.
      '40 units reviewed · 3 verified findings · this platform has no PDF renderer — the diagrams were reviewed from text only, not from their images':
          'Đã chấm 40 mục · 3 lỗi đã đối chiếu · thiết bị này không có bộ vẽ PDF nên sơ đồ chỉ được chấm từ văn bản',
      'This platform has no PDF renderer — the diagrams were reviewed from text only, not from their images.':
          'Thiết bị này không có bộ vẽ PDF; sơ đồ chỉ được chấm từ văn bản, không chấm từ ảnh trang.',
    };
    for (final entry in cases.entries) {
      expect(workspaceMessage(entry.key), entry.value);
    }
    expect(
      workspaceMessage(ApiService.quotaMessage(retryAfterSeconds: 120)),
      contains('2 phút'),
    );
    expect(
      workspaceMessage(ApiService.quotaMessage(retryAfterSeconds: 7200)),
      contains('2 giờ'),
    );
    expect(workspaceMessage(ApiService.quotaMessage()), contains('ngày mai'));
  });

  test(
    'real deterministic findings are translated without changing evidence',
    () {
      final document = SrsDocument(
        fileName: 'English requirements.docx',
        pageCount: 1,
        pageTexts: const ['Original evidence'],
        requirements: const [
          RequirementItem(
            id: 'UC01',
            text: 'UC01 Test\nMain flow:\n1. User logs in.',
            kind: RequirementKind.useCase,
          ),
          RequirementItem(
            id: 'UC01',
            text: 'UC01 Other goal',
            kind: RequirementKind.useCase,
          ),
        ],
      );

      // Exercise actual checker output so wording and coverage cannot drift.
      final findings = [
        ...const SyllabusChecks(RubricConfig.fallback).runAll(document),
        ...const ReferenceChecks().runAll(document),
      ];

      expect(findings, isNotEmpty);
      // 2026-09-25: findings carry BOTH languages, so the UI no longer
      // translates anything — it reads the Vietnamese twin directly. This is
      // the tripwire for the pair: a check that forgets a twin, or copies the
      // English string into both fields, fails right here.
      for (final finding in findings) {
        expect(
          finding.messageVi,
          isNot(finding.messageEn),
          reason: 'Thiếu bản tiếng Việt cho "${finding.messageEn}"',
        );
      }

      // Kiểm tra bảo toàn dữ liệu tài liệu gốc
      expect(document.pageTexts.single, 'Original evidence');
      expect(document.requirements.first.id, 'UC01');
      expect(workspaceLabel('Business rule'), 'Quy tắc nghiệp vụ');
      expect(workspaceLabel('Section'), 'Mục tài liệu');
    },
  );

  test('review progress uses Vietnamese and keeps requirement identity', () {
    expect(
      workspaceProgressLabel(
        const ReviewProgress(
          stage: ReviewStage.reviewing,
          completed: 3,
          total: 40,
          currentRequirementId: 'UC01',
        ),
      ),
      'Đang chấm 3/40 (UC01)…',
    );
    expect(
      workspaceProgressLabel(
        const ReviewProgress(stage: ReviewStage.verifying),
      ),
      'Đang đối chiếu trích dẫn…',
    );
  });
}
