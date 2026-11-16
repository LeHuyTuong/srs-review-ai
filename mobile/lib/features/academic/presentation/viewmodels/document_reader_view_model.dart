import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';

// Trạng thái đọc gắn với yêu cầu và phiên bản; vị trí xem không ghi vào lịch sử tài liệu.
class DocumentReadingState {
  const DocumentReadingState({this.page = 0, this.offset});
  final int page;
  final double? offset;
}

// Khóa truyền vào chứa yêu cầu và phiên bản để các bản nộp không dùng chung vị trí đọc.
final documentReaderProvider = NotifierProvider.autoDispose
    .family<DocumentReaderViewModel, DocumentReadingState, String>(
      DocumentReaderViewModel.new,
    );

// Giữ trang và vị trí cuộn khi chuyển chế độ đọc trong cùng vòng đời provider.
class DocumentReaderViewModel extends Notifier<DocumentReadingState> {
  DocumentReaderViewModel(this.key);
  final String key;
  @override
  DocumentReadingState build() {
    ref.watch(sessionScopeProvider);
    return const DocumentReadingState();
  }

  // Giới hạn trang theo tổng số trang để thao tác trước, sau không vượt phạm vi tài liệu.
  void selectPage(int page, int total) => state = DocumentReadingState(
    page: page.clamp(0, (total - 1).clamp(0, 10000)),
    offset: state.offset,
  );
  // Chỉ nhớ vị trí cuộn hữu hạn, không âm để có thể khôi phục chế độ đọc toàn màn hình.
  void rememberOffset(double value) {
    if (value.isFinite && value >= 0) {
      state = DocumentReadingState(page: state.page, offset: value);
    }
  }
}

// Chia nội dung mẫu thành trang ở tầng ViewModel; trang đầu luôn dành cho bìa.
class DocumentSampleData {
  DocumentSampleData(
    AcademicSnapshot snapshot,
    AcademicRecord review,
    int page,
  ) {
    final sample =
        (snapshot.data['documentSamples'] as Map)[review.text('documentTitle')]
            as Map?;
    final checks = (sample?['checks'] as List? ?? [])
        .map((v) => AcademicRecord(v as AcademicJson))
        .toList();
    final perPage =
        (checks.length / (review.integer('pageCount', 1) - 1).clamp(1, 10000))
            .ceil();
    pageChecks = page == 0
        ? const []
        : checks.skip((page - 1) * perPage).take(perPage).toList();
  }
  late final List<AcademicRecord> pageChecks;
}
