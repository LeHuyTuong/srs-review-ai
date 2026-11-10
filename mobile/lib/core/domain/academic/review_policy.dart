part of 'academic_models.dart';

// Đối chiếu tiêu chí với mục tài liệu: kết quả AI thật (fromAi) hoặc minh hoạ từ documentSamples (illustration).
/// Điểm AI của một tiêu chí, độc lập với lớp HTTP để domain không phụ thuộc service.
class AiCriterionScore {
  const AiCriterionScore({
    required this.score,
    this.issues = const [],
    this.contextNote,
  });

  /// Thang 0–10 của server.
  final int score;
  final List<AcademicRecord> issues;
  final String? contextNote;
}

class ReviewPolicy {
  /// Chế độ chấm Đạt/Chưa đạt: điểm AI từ 7/10 trở lên tính là đạt.
  static const passScore = 7;

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

  // Mục tài liệu đối chiếu cho một tiêu chí: REVIEW01–05 khớp theo vị trí, tiêu chí khác khớp tên.
  static AcademicRecord? _scenarioFor(
    RubricCriterion c,
    List<AcademicRecord> checks,
  ) {
    if (RegExp(r'^REVIEW0[1-5]$').hasMatch(c.id)) {
      final i = int.parse(c.id.substring(c.id.length - 1)) - 1;
      return i < checks.length ? checks[i] : null;
    }
    return checks
        .where(
          (v) => RegExp(v.text('match'), caseSensitive: false).hasMatch(c.name),
        )
        .firstOrNull;
  }

  static List<AcademicRecord> _checks(AcademicSnapshot s, String title) {
    final sample = (s.data['documentSamples'] as Map? ?? {})[title] as Map?;
    return (sample?['checks'] as List? ?? [])
        .map((c) => AcademicRecord(c as AcademicJson))
        .toList();
  }

  /// Đoạn văn bản gửi lên AI: mỗi tiêu chí bật AI có mục đối chiếu là một unit,
  /// `requirementId` = id tiêu chí để ghép điểm về đúng dòng rubric.
  static List<({String criterionId, String section, String text})> aiUnits(
    AcademicSnapshot s,
    AcademicRecord run,
    String title,
  ) {
    final rule = RuleSet(run.data['ruleSnapshot'] as AcademicJson);
    final checks = _checks(s, title);
    return [
      for (final c in rule.criteria.where(
        (c) => c.enabled && c.flag('aiEnabled'),
      ))
        if (_scenarioFor(c, checks) case final sc?
            when sc.text('text').trim().isNotEmpty)
          (
            criterionId: c.id,
            section: '$title · ${sc.name}',
            text: sc.text('text'),
          ),
    ];
  }

  /// Unit chấm từ văn bản trích của tệp nộp: mỗi tiêu chí bật AI một unit, dùng
  /// chung phần văn bản đã trích (cắt 12.000 ký tự) thay cho mẫu `documentSamples`.
  static List<({String criterionId, String section, String text})> fileUnits(
    RuleSet rule,
    String title,
    List<({String title, String text})> sections,
  ) {
    final body = sections
        .where((section) => section.text.trim().isNotEmpty)
        .map((section) => '## ${section.title}\n${section.text}')
        .join('\n\n');
    if (body.trim().isEmpty) return const [];
    final text = body.length > maxUnitChars
        ? body.substring(0, maxUnitChars)
        : body;
    return [
      for (final c in rule.criteria.where(
        (c) => c.enabled && c.flag('aiEnabled'),
      ))
        (criterionId: c.id, section: '$title · ${c.name}', text: text),
    ];
  }

  /// Trần ký tự mỗi unit gửi AI, tính cả văn bản trích từ tệp nộp.
  static const maxUnitChars = 12000;

  // Dựng kết quả minh họa từ nội dung mẫu và bản chụp Rule Set của lần chạy, không chấm tệp thật.
  static AcademicRecord illustration(
    AcademicSnapshot s,
    AcademicRecord run,
    String title,
  ) => _build(s, run, title, null, null);

  /// Kết quả từ AI thật: điểm 0–10 của server quy về thang điểm từng tiêu chí,
  /// nhận xét và lỗi lấy từ issue có trích dẫn đã kiểm ở server.
  /// [fromFile] = true khi chấm tệp nộp: không đối chiếu `documentSamples` nữa.
  static AcademicRecord fromAi(
    AcademicSnapshot s,
    AcademicRecord run,
    String title,
    Map<String, AiCriterionScore> ai, {
    String? model,
    bool fromFile = false,
  }) => _build(s, run, title, ai, model, fromFile: fromFile);

  static AcademicRecord _build(
    AcademicSnapshot s,
    AcademicRecord run,
    String title,
    Map<String, AiCriterionScore>? ai,
    String? model, {
    bool fromFile = false,
  }) {
    final rule = RuleSet(run.data['ruleSnapshot'] as AcademicJson);
    final checks = fromFile ? const <AcademicRecord>[] : _checks(s, title);
    final binary = rule.text('scoringMode') == 'binary';
    final results = <AcademicJson>[];
    final findings = <AcademicJson>[];
    for (final c in rule.criteria.where((c) => c.enabled)) {
      final scenario = _scenarioFor(c, checks);
      final real = ai?[c.id];
      if (ai != null && real != null) {
        final score = c.flag('suggestScore')
            ? binary
                  ? (real.score >= passScore ? c.maxScore : 0)
                  : (c.maxScore * real.score / 10 * 100).round() / 100
            : null;
        final first = real.issues.firstOrNull;
        results.add({
          'criterionId': c.id,
          'name': c.name,
          'maxScore': c.maxScore,
          'score': score,
          'aiScore': real.score,
          'comment':
              real.contextNote ??
              (first == null
                  ? 'AI không phát hiện vấn đề ở mục này.'
                  : first.text('suggestion')),
          if (first != null) 'issue': first.text('quote'),
          'needsVerification': true,
          'evidence': '$title · Mục ${scenario?.name ?? c.name}',
          'suggestions': c.flag('suggestSuggestions')
              ? [
                  for (final i in real.issues)
                    if (i.text('suggestion').isNotEmpty) i.text('suggestion'),
                ]
              : <String>[],
        });
        if (c.flag('suggestFindings')) {
          for (final (n, i) in real.issues.indexed) {
            findings.add({
              'id': '${run.id}-${c.id}-$n',
              'level': c.flag('critical') || i.text('severity') == 'high'
                  ? 'error'
                  : 'warning',
              'category': c.name,
              'message': i.text('suggestion'),
              'issue': i.text('quote'),
              if (c.flag('suggestSuggestions'))
                'suggestion': i.text('suggestion'),
              'proposedScore': score,
              'maxScore': c.maxScore,
              'pageRef': 'Mục ${scenario?.name ?? c.name}',
            });
          }
        }
        continue;
      }
      if (ai != null) {
        // Tiêu chí không gửi AI (tắt AI / không có mục đối chiếu / AI không chấm được): để giảng viên chấm tay.
        results.add({
          'criterionId': c.id,
          'name': c.name,
          'maxScore': c.maxScore,
          'score': null,
          'comment': c.flag('aiEnabled')
              ? 'AI chưa chấm được tiêu chí này. Giảng viên đối chiếu thủ công.'
              : 'Tiêu chí chấm thủ công.',
          'needsVerification': true,
          'evidence': scenario != null
              ? '$title · Mục ${scenario.name}'
              : 'Chưa có nội dung đối chiếu cho tiêu chí này.',
          'suggestions': <String>[],
        });
        continue;
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
      if (ai == null) 'illustrationVersion': 1,
      if (ai != null) 'aiSource': 'live',
      'model': ?model,
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
