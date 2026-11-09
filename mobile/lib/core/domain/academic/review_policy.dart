part of 'academic_models.dart';

// Kịch bản đối chiếu tiêu chí và ánh xạ kết quả từ AI Review Service.
class ReviewPolicy {
  // Ngưỡng có thể là số thập phân; thiếu điểm thủ công thì chưa xếp loại.
  static String rating(AcademicRecord run) {
    final score = run.data['overallScore'] as num?;
    final max = run.data['maxScore'] as num? ?? 0;
    if (score == null || max <= 0) return 'Chưa xếp loại';
    final rule = RuleSet(run.data['ruleSnapshot'] as AcademicJson);
    final percent = score / max * 100;
    return percent >= rule.passThreshold
        ? 'Đạt'
        : percent >= rule.improveThreshold
        ? 'Cần cải thiện'
        : 'Cần làm lại';
  }

  /// Ánh xạ kết quả trả về từ FastAPI `/review` (Gemini) sang bảng tiêu chí của Rule Set.
  static AcademicRecord fromLiveAiResult(
    AcademicSnapshot s,
    AcademicRecord run,
    String title, {
    required int scoreOutOf10,
    required List<Map<String, dynamic>> issues,
    String? contextNote,
  }) {
    final rule = RuleSet(run.data['ruleSnapshot'] as AcademicJson);
    final ratio = (scoreOutOf10.clamp(0, 10)) / 10.0;
    final results = <AcademicJson>[];
    final findings = <AcademicJson>[];
    final enabledCriteria = rule.criteria.where((c) => c.enabled).toList();

    for (var idx = 0; idx < enabledCriteria.length; idx++) {
      final c = enabledCriteria[idx];
      final issueMap = idx < issues.length
          ? issues[idx]
          : (issues.isNotEmpty ? issues.first : null);
      final issueDesc =
          (issueMap?['description'] as String?) ??
          (issueMap?['message'] as String?) ??
          '';
      final suggestionText =
          (issueMap?['suggestion'] as String?) ??
          (issueMap?['fix'] as String?) ??
          'Rà soát và bổ sung đặc tả chi tiết hơn cho mục này.';
      final severity =
          (issueMap?['severity'] as String?)?.toLowerCase() ?? 'warning';

      final score = c.flag('aiEnabled') && c.flag('suggestScore')
          ? rule.text('scoringMode') == 'binary'
                ? (ratio >= 0.7 ? c.maxScore : 0)
                : (c.maxScore * ratio * 100).round() / 100
          : null;

      results.add({
        'criterionId': c.id,
        'name': c.name,
        'maxScore': c.maxScore,
        'score': score,
        'comment': issueDesc.isNotEmpty
            ? issueDesc
            : (contextNote ?? 'AI đánh giá đạt mức $scoreOutOf10/10.'),
        if (issueDesc.isNotEmpty) 'issue': issueDesc,
        'needsVerification': true,
        'evidence': contextNote?.isNotEmpty == true
            ? '$title · $contextNote'
            : '$title · Đánh giá trực tiếp qua FastAPI AI Review Service.',
        'suggestions':
            c.flag('aiEnabled') &&
                c.flag('suggestSuggestions') &&
                suggestionText.isNotEmpty
            ? [suggestionText]
            : <String>[],
      });

      if (c.flag('aiEnabled') &&
          c.flag('suggestFindings') &&
          issueDesc.isNotEmpty) {
        findings.add({
          'id': '${run.id}-${c.id}',
          'level': c.flag('critical') ||
                  severity == 'high' ||
                  severity == 'critical' ||
                  severity == 'error' ||
                  ratio <= 0.5
              ? 'error'
              : 'warning',
          'category': c.name,
          'message': issueDesc,
          'issue': issueDesc,
          if (c.flag('suggestSuggestions')) 'suggestion': suggestionText,
          'proposedScore': score,
          'maxScore': c.maxScore,
          'pageRef': 'Tài liệu $title',
        });
      }
    }

    return AcademicRecord({
      ...run.toJson(),
      'sampleDocumentTitle': title,
      'aiSource': 'live',
      'illustrationVersion': 1,
      'evaluationStatus': 'completed',
      'criterionResults': results,
      'findings': findings,
      'maxScore': results.fold<num>(0, (n, c) => n + (c['maxScore'] as num)),
      'overallScore':
          results.isNotEmpty && results.every((c) => c['score'] != null)
          ? (results.fold<num>(0, (n, c) => n + (c['score'] as num)) * 100)
                    .round() /
                100
          : null,
    });
  }

  // Dựng kết quả đối chiếu cục bộ khi chạy offline / unit test không có FastAPI server.
  static AcademicRecord illustration(
    AcademicSnapshot s,
    AcademicRecord run,
    String title,
  ) {
    final rule = RuleSet(run.data['ruleSnapshot'] as AcademicJson);
    final sample = (s.data['documentSamples'] as Map? ?? {})[title] as Map?;
    final checks = (sample?['checks'] as List? ?? [])
        .map((c) => AcademicRecord(c as AcademicJson))
        .toList();
    final results = <AcademicJson>[];
    final findings = <AcademicJson>[];
    for (final c in rule.criteria.where((c) => c.enabled)) {
      AcademicRecord? scenario;
      // Tiêu chí mẫu cũ REVIEW01–REVIEW05 khớp theo vị trí; tiêu chí khác khớp tên bằng mẫu tìm kiếm.
      if (RegExp(r'^REVIEW0[1-5]$').hasMatch(c.id)) {
        final i = int.parse(c.id.substring(c.id.length - 1)) - 1;
        if (i < checks.length) scenario = checks[i];
      } else {
        scenario = checks
            .where(
              (v) => RegExp(
                v.text('match'),
                caseSensitive: false,
              ).hasMatch(c.name),
            )
            .firstOrNull;
      }
      // Chỉ đề xuất điểm khi tiêu chí bật AI, cho phép gợi ý điểm và có nội dung mẫu đối chiếu.
      final score =
          c.flag('aiEnabled') && c.flag('suggestScore') && scenario != null
          ? rule.text('scoringMode') == 'binary'
                ? (scenario.text('issue').isEmpty ? c.maxScore : 0)
                : (c.maxScore * (scenario.data['ratio'] as num) * 100).round() /
                      100
          : null;
      results.add({
        'criterionId': c.id,
        'name': c.name,
        'maxScore': c.maxScore,
        'score': score,
        'comment':
            scenario?.text('comment') ?? 'Tiêu chí cần được đối chiếu thêm.',
        if (scenario?.data['issue'] != null) 'issue': scenario!.data['issue'],
        'needsVerification': true,
        'evidence': scenario != null
            ? '$title · Mục ${scenario.name}: ${scenario.text('text')}'
            : 'Chưa có nội dung đối chiếu cho tiêu chí này.',
        'suggestions':
            c.flag('aiEnabled') &&
                c.flag('suggestSuggestions') &&
                scenario != null
            ? [scenario.text('suggestion')]
            : <String>[],
      });
      if (c.flag('aiEnabled') &&
          c.flag('suggestFindings') &&
          scenario != null &&
          scenario.text('issue').isNotEmpty) {
        findings.add({
          'id': '${run.id}-${c.id}',
          'level': c.flag('critical') || (scenario.data['ratio'] as num) <= .5
              ? 'error'
              : 'warning',
          'category': c.name,
          'message': scenario.text('comment'),
          'issue': scenario.text('issue'),
          if (c.flag('suggestSuggestions'))
            'suggestion': scenario.text('suggestion'),
          'proposedScore': score,
          'maxScore': c.maxScore,
          'pageRef': 'Mục ${scenario.name}',
        });
      }
    }
    return AcademicRecord({
      ...run.toJson(),
      'sampleDocumentTitle': title,
      'illustrationVersion': 1,
      'evaluationStatus': 'completed',
      'criterionResults': results,
      'findings': findings,
      'maxScore': results.fold<num>(0, (n, c) => n + (c['maxScore'] as num)),
      // Chỉ cộng tổng khi mọi tiêu chí đều có điểm; còn tiêu chí thủ công thì chưa xếp loại.
      'overallScore':
          results.isNotEmpty && results.every((c) => c['score'] != null)
          ? (results.fold<num>(0, (n, c) => n + (c['score'] as num)) * 100)
                    .round() /
                100
          : null,
    });
  }

  // Chỉ làm mới cách trình bày bản minh họa cũ, không lưu lại kết quả lịch sử.
  static AcademicRecord currentIllustration(
    AcademicSnapshot s,
    AcademicRecord run,
    String title,
  ) {
    final legacy =
        run.text('evaluationStatus') == 'completed' &&
        run.data['illustrationVersion'] == null &&
        (run
                .values('findings')
                .any(
                  (f) =>
                      RegExp('Finding mô phỏng|Cần xác minh “')
                          .hasMatch(f['message'].toString()),
                ) ||
            run
                .values('criterionResults')
                .any(
                  (c) =>
                      c['suggestions'].toString().contains('Gợi ý mô phỏng:'),
                ));
    return legacy ? illustration(s, run, title) : run;
  }

  // Phân biệt chưa chạy, đang tải và lỗi trước khi đếm phát hiện; không dùng số 0 để che lỗi AI.
  static String aiLabel(AcademicSnapshot s, AcademicRecord r) {
    final raw = s.evaluation(r);
    if (raw == null) return 'AI chưa có kết quả';
    if (raw.text('evaluationStatus') == 'loading') return 'AI đang xử lý';
    if (raw.text('evaluationStatus') == 'error') {
      return 'AI chưa hoàn tất · Cần thử lại';
    }
    final e = currentIllustration(s, raw, r.text('documentTitle'));
    final fs = e.values('findings');
    final counts = [
      (fs.where((f) => f['level'] == 'error').length, 'lỗi'),
      (fs.where((f) => f['level'] == 'warning').length, 'cảnh báo'),
      (
        e
            .values('criterionResults')
            .fold<int>(0, (n, c) => n + (c['suggestions'] as List).length),
        'gợi ý',
      ),
    ];
    final parts = counts.where((p) => p.$1 > 0).map((p) => '${p.$1} ${p.$2}');
    return 'AI đề xuất: ${parts.isEmpty ? 'Không phát hiện lỗi' : parts.join(' · ')}';
  }
}
