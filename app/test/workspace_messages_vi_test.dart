import 'package:flutter_test/flutter_test.dart';
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

      // Các thông báo mẫu thực tế do SyllabusChecks và ReferenceChecks sinh ra
      final sampleFindingMessages = [
        'Document has fewer than 20 use cases.',
        'Use case UC01 exceeds maximum recommended size.',
        'Unreferenced business rule BR01 detected.',
      ];

      for (final msg in sampleFindingMessages) {
        expect(
          workspaceMessage(msg),
          isNot(msg),
          reason: 'Thông báo "$msg" chưa được dịch sang tiếng Việt',
        );
      }

      // Kiểm tra bảo toàn dữ liệu tài liệu gốc
      expect(document.pageTexts.single, 'Original evidence');
      expect(document.requirements.first.id, 'UC01');
      expect(workspaceLabel('Business rule'), 'Quy tắc nghiệp vụ');
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
