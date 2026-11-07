import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/report_sharer.dart';

// Trạng thái tương tác AI theo yêu cầu đánh giá, tách riêng kết quả lưu trong Repository.
class ReviewPanelState {
  const ReviewPanelState({
    this.attentionOnly = true,
    this.expanded = const {},
    this.added = const {},
    this.error = '',
  });
  final bool attentionOnly;
  final Set<String> expanded, added;
  final String error;
}

// Giữ phần mở rộng và phát hiện đã thêm theo yêu cầu; đổi phiên sẽ khởi tạo lại trạng thái tương tác.
final reviewPanelProvider = NotifierProvider.autoDispose
    .family<ReviewPanelViewModel, ReviewPanelState, String>(
      ReviewPanelViewModel.new,
    );

// Điều phối tương tác AI và hiển thị lỗi; kết quả và nhật ký lưu ở kho học vụ chung.
class ReviewPanelViewModel extends Notifier<ReviewPanelState> {
  ReviewPanelViewModel(this.id);
  final String id;
  AiPanelPresentation present(
    AcademicSnapshot snapshot,
    AcademicRecord review,
  ) => AiPanelPresentation(snapshot, review, state);
  void toggleAll(AiPanelPresentation panel) => expand(
    panel.allExpanded
        ? {}
        : panel.visible.map((c) => c.text('criterionId')).toSet(),
  );
  void toggleCriterion(String id, bool value) => expand(
    value
        ? {...state.expanded, id}
        : state.expanded.where((v) => v != id).toSet(),
  );
  @override
  ReviewPanelState build() {
    ref.watch(sessionScopeProvider);
    return const ReviewPanelState();
  }

  void attention(bool value) => state = ReviewPanelState(
    attentionOnly: value,
    expanded: state.expanded,
    added: state.added,
  );
  void expand(Set<String> values) => state = ReviewPanelState(
    attentionOnly: state.attentionOnly,
    expanded: values,
    added: state.added,
  );
  /// Xuất kết quả AI thành tệp Markdown qua hộp chia sẻ của hệ điều hành.
  /// Trả về false khi người dùng đóng hộp chia sẻ hoặc xuất lỗi.
  Future<bool> exportReport(AiPanelPresentation panel) async {
    try {
      final shared = await ref.read(reportSharerProvider).shareText(
        fileName: AiReportExporter.fileName(panel),
        mimeType: 'text/markdown',
        content: AiReportExporter.markdown(panel),
      );
      if (shared) {
        await ref
            .read(analyticsServiceProvider)
            .logExportReport(format: 'md', documentId: id);
      }
      return shared;
    } catch (e) {
      if (ref.mounted) {
        state = ReviewPanelState(
          attentionOnly: state.attentionOnly,
          expanded: state.expanded,
          added: state.added,
          error: 'Không xuất được báo cáo: $e',
        );
      }
      return false;
    }
  }

  // Xóa lỗi cũ trước khi chạy lại; chỉ cập nhật giao diện nếu phiên khởi chạy còn hiệu lực.
  Future<void> run() async {
    final scope = ref.read(sessionScopeProvider);
    state = ReviewPanelState(
      attentionOnly: state.attentionOnly,
      expanded: state.expanded,
      added: state.added,
    );
    try {
      await ref.read(academicViewModelProvider.notifier).runEvaluation(id);
      await ref.read(analyticsServiceProvider).logRunAiReview(id);
      if (ref.mounted && scope.active) {
        state = ReviewPanelState(
          attentionOnly: state.attentionOnly,
          expanded: state.expanded,
          added: state.added,
        );
      }
    } catch (e) {
      if (ref.mounted && scope.active) {
        state = ReviewPanelState(
          attentionOnly: state.attentionOnly,
          expanded: state.expanded,
          added: state.added,
          error: e is AcademicFailure
              ? e.message
              : 'Không thể tạo kết quả. Vui lòng thử lại.',
        );
      }
    }
  }

  // Trong vòng đời bảng AI, phát hiện đã thêm thành công không được thêm lần nữa.
  // Chỉ đánh dấu đã thêm sau khi lưu phản hồi nháp thành công.
  Future<void> addFinding(AcademicRecord f) async {
    final scope = ref.read(sessionScopeProvider);
    if (state.added.contains(f.id)) return;
    try {
      await ref.read(academicViewModelProvider.notifier).addFeedback(id, {
        'severity': f.text('level') == 'error' ? 'Major' : 'Minor',
        'category': f.text('category'),
        'pageRef': f.text('pageRef'),
        'message': f.text('message'),
      });
      if (ref.mounted && scope.active) {
        state = ReviewPanelState(
          attentionOnly: state.attentionOnly,
          expanded: state.expanded,
          added: {...state.added, f.id},
        );
      }
    } catch (e) {
      if (ref.mounted && scope.active) {
        state = ReviewPanelState(
          attentionOnly: state.attentionOnly,
          expanded: state.expanded,
          added: state.added,
          error: e is AcademicFailure ? e.message : 'Không thể thêm phản hồi.',
        );
      }
    }
  }
}

// Chuẩn bị toàn bộ dữ liệu bảng AI trước khi dựng Widget; giữ nguyên tiêu chí và thứ tự.
class AiPanelPresentation {
  AiPanelPresentation(this.snapshot, this.review, this.state);
  final AcademicSnapshot snapshot;
  final AcademicRecord review;
  final ReviewPanelState state;
  List<AcademicRecord> get previewFindings => findings.take(3).toList();
  String get rating => ReviewPolicy.rating(evaluation!);
  late final raw = snapshot.evaluation(review);
  late final evaluation = raw == null
      ? null
      : ReviewPolicy.currentIllustration(
          snapshot,
          raw!,
          review.text('documentTitle'),
        );
  late final rule = evaluation?.data['ruleSnapshot'] is Map
      ? RuleSet(evaluation!.data['ruleSnapshot'] as AcademicJson)
      : snapshot.reviewRule(review);
  late final runs = snapshot
      .reviewRows('evaluations')
      .where((v) => v.text('reviewId') == review.id)
      .toList();
  late final results = (evaluation?.values('criterionResults') ?? [])
      .map((v) => AcademicRecord(v as AcademicJson))
      .toList();
  late final findings = (evaluation?.values('findings') ?? [])
      .map((v) => AcademicRecord(v as AcademicJson))
      .toList();
  late final attention = results
      .where(
        (c) =>
            c.data['score'] == null ||
            (c.data['score'] as num) < (c.data['maxScore'] as num),
      )
      .toList();
  late final visible = state.attentionOnly && attention.isNotEmpty
      ? attention
      : results;
  late final canRun =
      !snapshot.completed(review) &&
      rule?.flag('aiEnabled') == true &&
      rule?.active == true &&
      rule!.criteria.any((c) => c.enabled) &&
      snapshot.project(review.text('projectId'))?.text('state') != 'archived' &&
      snapshot.classRoom(review.text('classId'))?.archived == false;
  num get max => evaluation?.data['maxScore'] as num? ?? 0;
  num? get score => evaluation?.data['overallScore'] as num?;
  num? get percent => score != null && max > 0 ? score! / max * 100 : null;
  int get passed =>
      results.where((c) => c.data['score'] == c.data['maxScore']).length;
  int get improve => attention.where((c) => c.data['score'] != null).length;
  int get unscored => results.where((c) => c.data['score'] == null).length;
  bool get allExpanded =>
      visible.every((c) => state.expanded.contains(c.text('criterionId')));
  List<AcademicRecord> findingsFor(String name) =>
      findings.where((f) => f.text('category') == name).toList();
  List<AcademicRecord> get unmatchedFindings => findings
      .where((f) => !results.any((c) => c.name == f.text('category')))
      .toList();
  int get enabledCriteria => rule?.criteria.where((c) => c.enabled).length ?? 0;
}

/// Dựng báo cáo Markdown từ kết quả AI; hàm thuần để test không cần plugin.
abstract final class AiReportExporter {
  static String fileName(AiPanelPresentation panel) {
    final title = panel.review
        .text('documentTitle', 'srs')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'bao-cao-ai-${title.isEmpty ? 'srs' : title.toLowerCase()}.md';
  }

  static String _n(Object? v) => v is num
      ? (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1))
      : '—';

  static String _cell(String v) =>
      v.replaceAll('|', '\\|').replaceAll(RegExp(r'\s*\n\s*'), ' ');

  static String markdown(AiPanelPresentation panel) {
    final r = panel.review;
    final b = StringBuffer()
      ..writeln('# Báo cáo đánh giá AI — ${r.text('documentTitle')}')
      ..writeln()
      ..writeln('- Dự án: ${r.text('projectName')}')
      ..writeln('- Lớp / nhóm: ${r.text('classCode')} · ${r.text('groupName')}')
      ..writeln('- Phiên bản: ${r.text('version')}')
      ..writeln('- Điểm tham khảo: **${_n(panel.score)} / ${_n(panel.max)}**')
      ..writeln(
        '- Tổng hợp: ${panel.passed} đạt · ${panel.improve} cần cải thiện · '
        '${panel.unscored} chưa chấm',
      )
      ..writeln()
      ..writeln('## Điểm theo tiêu chí')
      ..writeln()
      ..writeln('| Mã | Tiêu chí | Điểm | Tối đa |')
      ..writeln('|---|---|---|---|');
    for (final c in panel.results) {
      b.writeln(
        '| ${_cell(c.text('criterionId'))} | ${_cell(c.name)} | '
        '${c.data['score'] == null ? 'Chấm thủ công' : _n(c.data['score'])} | '
        '${_n(c.data['maxScore'])} |',
      );
    }
    b
      ..writeln()
      ..writeln('## Phát hiện (${panel.findings.length})');
    for (final f in panel.findings) {
      b
        ..writeln()
        ..writeln('- **${f.text('category', 'Khác')}** — ${f.text('issue', f.text('message'))}');
      if (f.text('suggestion').isNotEmpty) {
        b.writeln('  - Gợi ý: ${f.text('suggestion')}');
      }
    }
    b
      ..writeln()
      ..writeln('_Kết quả AI chỉ mang tính tham khảo; giảng viên quyết định cuối cùng._');
    return b.toString();
  }
}
