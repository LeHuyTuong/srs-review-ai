part of 'academic_models.dart';

// Kịch bản minh họa được trích từ documentSamples.ts; tuyệt đối không đọc/chấm tệp thật.
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

  // Dựng kết quả minh họa từ nội dung mẫu và bản chụp Rule Set của lần chạy, không chấm tệp thật.
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
                .jsonRecords('findings')
                .any(
                  (f) => RegExp(
                    'Finding mô phỏng|Cần xác minh “',
                  ).hasMatch((f['message'] as Object? ?? '').toString()),
                ) ||
            run
                .jsonRecords('criterionResults')
                .any(
                  (c) => (c['suggestions'] as Object? ?? '')
                      .toString()
                      .contains('Gợi ý mô phỏng:'),
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
    final fs = e.jsonRecords('findings');
    final counts = [
      (fs.where((f) => f['level'] == 'error').length, 'lỗi'),
      (fs.where((f) => f['level'] == 'warning').length, 'cảnh báo'),
      (
        e
            .jsonRecords('criterionResults')
            .fold<int>(0, (n, c) => n + (c['suggestions'] as List).length),
        'gợi ý',
      ),
    ];
    final parts = counts.where((p) => p.$1 > 0).map((p) => '${p.$1} ${p.$2}');
    return 'AI đề xuất: ${parts.isEmpty ? 'Không phát hiện lỗi' : parts.join(' · ')}';
  }
}
