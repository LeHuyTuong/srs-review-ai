part of 'academic_view_model.dart';

// Lượt đánh giá, phản hồi và nhật ký được lưu cùng bản chụp mô phỏng có kiểm tra revision.
extension ReviewActions on AcademicViewModel {
  AcademicJson reviewData(AcademicSnapshot s) =>
      AcademicRecord(s.data['reviewState'] as AcademicJson).toJson();

  /// Ghi trạng thái lên bài nộp của sinh viên sau khi lượt duyệt đã lưu.
  /// Lỗi (offline, rules) chỉ ghi log: thao tác của giảng viên vẫn giữ nguyên.
  void syncSubmissionStatus(
    String submissionId,
    Future<void> Function(SubmissionStatusSync sync) write,
  ) {
    final sync = submissionStatusSync;
    if (!isMounted || sync == null || submissionId.isEmpty) return;
    final crashlytics = crashlyticsService;
    unawaited(() async {
      try {
        await write(sync);
      } on Object catch (error, stackTrace) {
        await crashlytics.logError(
          error,
          stackTrace,
          reason: 'submission_status_sync_error',
          keys: {'submission_id': submissionId},
        );
      }
    }());
  }

  /// Bài nộp thật vừa chuyển waiting → inReview thì báo "Đang chấm".
  void syncReviewing(AcademicRecord before) {
    final submissionId = before.text('submissionId');
    if (before.text('supervisorStatus') != 'waiting') return;
    syncSubmissionStatus(
      submissionId,
      (sync) => sync.reviewing(
        submissionId,
        reviewId: before.id,
        fileName: before.text('fileName'),
      ),
    );
  }

  String actor(AcademicSnapshot s) =>
      (s.data['currentUser'] as Map)['name'].toString();
  String timestamp() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} · ${p(d.hour)}:${p(d.minute)}';
  }

  AcademicJson event(
    AcademicSnapshot s,
    String id,
    String title, {
    String tone = 'brand',
    String? quote,
    String? version,
    List<String>? selected,
  }) => {
    'id': nextId('evt'),
    'reviewId': id,
    'time': timestamp(),
    'actor': actor(s),
    'title': title,
    'tone': tone,
    'quote': ?quote,
    'documentVersion': ?version,
    'selectedFeedbackIds': ?selected,
  };
  // Chặn ghi lượt đã kết thúc, dự án hoặc lớp lưu trữ; thao tác giảng viên còn phải qua điều kiện AI.
  AcademicRecord writableReview(
    AcademicSnapshot s,
    String id, {
    bool ai = false,
  }) {
    final r = s.review(id);
    if (r == null) {
      throw const AcademicFailure('Không tìm thấy yêu cầu đánh giá.');
    }
    if (s.completed(r)) {
      throw const AcademicFailure(
        'Đánh giá đã hoàn tất; lịch sử được giữ nguyên.',
      );
    }
    final p = s.project(r.text('projectId'));
    if (p == null || p.text('state') == 'archived') {
      throw const AcademicFailure(
        'Dự án đã lưu trữ hoặc không còn tồn tại, chỉ được xem.',
      );
    }
    final cls = s.projectClass(p);
    if (cls != null) activeClass(s, cls.id);
    final block = s.supervisorBlock(r);
    if (!ai && block != null) throw AcademicFailure(block);
    return r;
  }

  // Ghép dữ liệu đánh giá rồi tính lại lượt đang mở ở nhóm và lớp để số đếm luôn cùng bản chụp.
  AcademicSnapshot withReview(AcademicSnapshot s, AcademicJson data) {
    var next = AcademicSnapshot({...s.toJson(), 'reviewState': data});
    next = next.replaceCollection(
      'groups',
      next.groups
          .map(
            (g) => {
              ...g.toJson(),
              'pendingReviews': next
                  .reviewRows('requests')
                  .where(
                    (r) =>
                        !next.completed(r) &&
                        next.project(r.text('projectId'))?.text('groupId') ==
                            g.id,
                  )
                  .length,
            },
          )
          .toList(),
    );
    return recountClasses(next);
  }

  // Đưa một bài nộp thật (collection submissions) vào hàng chờ duyệt của giảng viên.
  // Mỗi bài nộp chỉ vào hàng chờ một lần; dự án lưu trữ hoặc mất thì từ chối.
  Future<void> queueSubmission(StudentSubmission sub) async {
    var reviewId = '';
    await mutate((s) {
      if (sub.id.isNotEmpty &&
          (s
                  .reviewRows('requests')
                  .any((r) => r.text('submissionId') == sub.id) ||
              s
                  .reviewRows('versions')
                  .any((v) => v.text('submissionId') == sub.id))) {
        throw const AcademicFailure('Bài nộp đã có trong hàng chờ duyệt.');
      }
      final p = s.project(sub.projectId);
      if (p == null || p.text('state') == 'archived') {
        throw const AcademicFailure('Bài nộp chưa gắn dự án đang hoạt động.');
      }
      // Nộp lại cho cùng dự án: thêm phiên bản vào yêu cầu đang có thay vì
      // mở yêu cầu mới, để lịch sử và so sánh điểm AI theo phiên bản.
      final existing = s
          .reviewRows('requests')
          .where(
            (r) =>
                r.text('projectId') == p.id &&
                r.text('submissionId').isNotEmpty,
          )
          .lastOrNull;
      if (existing != null) {
        reviewId = existing.id;
        return _appendVersion(s, existing, sub);
      }
      final cls = s.projectClass(p);
      final g = s.group(p.text('groupId'));
      final id = nextId('review');
      reviewId = id;
      final at = timestamp();
      final d = reviewData(s);
      d['requests'] = [
        ...s.reviewRows('requests').map((r) => r.toJson()),
        {
          'id': id,
          'projectId': p.id,
          'classCode': cls?.code ?? '',
          'groupName': g?.name ?? '',
          'projectName': p.text('name'),
          'semesterId': cls?.semesterId ?? '',
          'courseId': cls?.courseId ?? '',
          'classId': cls?.id ?? '',
          'groupId': p.text('groupId'),
          'documentTitle': 'Tài liệu SRS',
          'version': 'v1',
          'submitter': sub.studentName,
          'submittedAt': at,
          'requestedAt': at,
          'documentStatus': 'submitted',
          'aiStatus': 'notRun',
          'supervisorStatus': 'waiting',
          'revisionRound': 0,
          'fileName': sub.fileName,
          'fileType': _fileType(sub.fileName),
          'fileUrl': sub.fileUrl,
          'submissionId': sub.id,
          'contentHash': sub.contentHash,
          'requestedTs': DateTime.now().millisecondsSinceEpoch,
        },
      ];
      d['audit'] = [
        ...s.valuesOfReview('audit'),
        event(s, id, '${actor(s)} đưa bài nộp vào hàng chờ duyệt.'),
      ];
      return withReview(s, d);
    });
    syncSubmissionStatus(
      sub.id,
      (sync) => sync.queued(sub.id, reviewId: reviewId),
    );
  }

  /// Thêm v(n+1) cho [r]: dòng mới isCurrent, các dòng cũ thôi isCurrent.
  /// Tệp trùng sha256 với một phiên bản trước thì từ chối, không đổi gì.
  AcademicSnapshot _appendVersion(
    AcademicSnapshot s,
    AcademicRecord r,
    StudentSubmission sub,
  ) {
    // versionsFor dựng sẵn dòng hiện tại cho dữ liệu cũ chưa lưu phiên bản.
    final versions = s.versionsFor(r).map((v) => v.toJson()).toList();
    for (final v in versions) {
      if (v['isCurrent'] == true && (v['contentHash'] ?? '') == '') {
        v['contentHash'] = r.text('contentHash');
      }
    }
    if (sub.contentHash.isNotEmpty) {
      final same = versions
          .where((v) => v['contentHash'] == sub.contentHash)
          .firstOrNull;
      if (same != null) {
        throw AcademicFailure(
          'File giống hệt ${same['version']}. Không đưa vào hàng chờ chấm lại.',
        );
      }
    }
    final last = versions
        .map((v) => int.tryParse('${v['version']}'.replaceFirst('v', '')) ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    final version = 'v${last + 1}';
    final at = timestamp();
    final d = reviewData(s);
    d['versions'] = [
      ...s
          .reviewRows('versions')
          .where((v) => v.text('reviewId') != r.id)
          .map((v) => v.toJson()),
      for (final v in versions) {...v, 'isCurrent': false},
      {
        'id': '${r.id}-$version',
        'reviewId': r.id,
        'version': version,
        'fileName': sub.fileName,
        'fileType': _fileType(sub.fileName),
        'fileUrl': sub.fileUrl,
        'submittedAt': at,
        'submitter': sub.studentName,
        'documentStatus': 'resubmitted',
        'supervisorStatus': 'waiting',
        'feedbackCount': 0,
        'isCurrent': true,
        'submissionId': sub.id,
        'contentHash': sub.contentHash,
      },
    ];
    d['requests'] = [
      for (final v in s.reviewRows('requests'))
        if (v.id == r.id)
          {
            ...v.toJson(),
            'version': version,
            'fileName': sub.fileName,
            'fileType': _fileType(sub.fileName),
            'fileUrl': sub.fileUrl,
            'submissionId': sub.id,
            'contentHash': sub.contentHash,
            'submitter': sub.studentName,
            'submittedAt': at,
            'requestedAt': at,
            'documentStatus': 'resubmitted',
            'supervisorStatus': 'waiting',
            'aiStatus': 'notRun',
            'revisionRound': v.integer('revisionRound') + 1,
            'requestedTs': DateTime.now().millisecondsSinceEpoch,
          }
        else
          v.toJson(),
    ];
    d['audit'] = [
      ...s.valuesOfReview('audit'),
      event(
        s,
        r.id,
        '${actor(s)} đưa bản nộp lại $version vào hàng chờ duyệt.',
      ),
    ];
    return withReview(s, d);
  }

  // Chỉ chuyển waiting sang inReview; chụp Rule Set nếu chưa có và ghi sự kiện bắt đầu cùng lần lưu.
  Future<void> startReview(String id) async {
    AcademicRecord? before;
    await mutate((s) {
      final r = writableReview(s, id);
      if (r.text('supervisorStatus') != 'waiting') return s;
      before = r;
      final d = reviewData(s);
      d['requests'] = [
        for (final v in s.reviewRows('requests'))
          if (v.id == id)
            {
              ...v.toJson(),
              'supervisorStatus': 'inReview',
              'ruleSnapshot':
                  v.data['ruleSnapshot'] ?? s.reviewRule(r)?.toJson(),
            }
          else
            v.toJson(),
      ];
      d['audit'] = [
        ...s.valuesOfReview('audit'),
        event(s, id, '${actor(s)} bắt đầu đánh giá.'),
      ];
      return withReview(s, d);
    });
    if (before case final r?) syncReviewing(r);
  }

  // Thêm phản hồi nháp theo phiên bản hiện tại; nếu đang waiting thì đồng thời bắt đầu đánh giá.
  Future<void> addFeedback(String id, AcademicJson input) async {
    AcademicRecord? before;
    await mutate((s) {
      final r = writableReview(s, id);
      before = r;
      final message = input['message']?.toString().trim() ?? '';
      if (message.isEmpty) {
        throw const AcademicFailure('Nhập nội dung phản hồi.');
      }
      final d = reviewData(s);
      if (r.text('supervisorStatus') == 'waiting') {
        d['requests'] = [
          for (final v in s.reviewRows('requests'))
            if (v.id == id)
              {
                ...v.toJson(),
                'supervisorStatus': 'inReview',
                'ruleSnapshot':
                    v.data['ruleSnapshot'] ?? s.reviewRule(r)?.toJson(),
              }
            else
              v.toJson(),
        ];
      }
      d['feedback'] = [
        ...s.valuesOfReview('feedback'),
        {
          if (input['pageRef'] != null) 'pageRef': input['pageRef'],
          'id': nextId('fb'),
          'reviewId': id,
          'version': r.text('version'),
          'message': message,
          'severity': input['severity'] ?? 'Major',
          'category':
              input['category'] ?? s.strings('feedbackCategories').first,
          'author': actor(s),
          'createdAt': timestamp(),
          'official': false,
        },
      ];
      d['audit'] = [
        ...s.valuesOfReview('audit'),
        if (r.text('supervisorStatus') == 'waiting')
          event(s, id, '${actor(s)} bắt đầu đánh giá.'),
        event(
          s,
          id,
          'Giảng viên thêm phản hồi.',
          tone: 'amber',
          quote: '“$message”',
        ),
      ];
      return withReview(s, d);
    });
    if (before case final r?) syncReviewing(r);
  }

  // Chỉ tác giả được sửa hoặc bỏ phản hồi chưa công bố trong dự án, lớp còn cho phép ghi.
  Future<void> updateFeedback(
    String id, {
    String? message,
    bool remove = false,
  }) => mutate((s) {
    final f = s.reviewRows('feedback').where((f) => f.id == id).firstOrNull;
    if (f == null || f.flag('official') || f.text('author') != actor(s)) {
      throw const AcademicFailure(
        'Phản hồi thuộc lịch sử hoặc không thuộc giảng viên hiện tại.',
      );
    }
    final r = s.review(f.text('reviewId'));
    final p = r == null ? null : s.project(r.text('projectId'));
    if (p == null || p.text('state') == 'archived') {
      throw const AcademicFailure('Dự án chỉ đọc.');
    }
    final cls = s.projectClass(p);
    if (cls != null) activeClass(s, cls.id);
    if (!remove && (message == null || message.trim().isEmpty)) {
      throw const AcademicFailure('Nhập nội dung phản hồi.');
    }
    final d = reviewData(s);
    d['feedback'] = [
      for (final v in s.reviewRows('feedback'))
        if (v.id != id)
          v.toJson()
        else if (!remove)
          {...v.toJson(), 'message': message!.trim()},
    ];
    return withReview(s, d);
  });

  // Chỉ phản hồi được chọn của phiên bản hiện tại trở thành chính thức; quyết định không thể sửa.
  Future<void> decideReview(
    String id,
    String decision, {
    String note = '',
    List<String> included = const [],
    String severity = 'Major',
    String? category,
  }) async {
    var submissionId = '';
    await mutate((s) {
      final r = writableReview(s, id);
      submissionId = r.text('submissionId');
      if (!['approved', 'needsRevision', 'notAccepted'].contains(decision)) {
        throw const AcademicFailure('Quyết định không hợp lệ.');
      }
      if (decision != 'approved' && note.trim().isEmpty) {
        throw const AcademicFailure('Cần lý do/phản hồi cho quyết định này.');
      }
      final d = reviewData(s);
      final selected = included.toSet();
      final feedback = s.reviewRows('feedback').map((v) => v.toJson()).toList();
      // Yêu cầu chỉnh sửa tạo thêm phản hồi tổng quan và tự chọn phản hồi đó để công bố trong quyết định.
      if (decision == 'needsRevision') {
        final fid = nextId('fb');
        selected.add(fid);
        feedback.add({
          'id': fid,
          'reviewId': id,
          'version': r.text('version'),
          'message': note.trim(),
          'severity': severity,
          'category': category ?? s.strings('feedbackCategories')[1],
          'author': actor(s),
          'createdAt': timestamp(),
          'official': false,
        });
      }
      // Chỉ công bố phản hồi được chọn khớp yêu cầu và phiên bản hiện tại; ID ở bản nộp khác bị loại.
      final validIds = feedback
          .where(
            (f) =>
                f['reviewId'] == id &&
                f['version'] == r.text('version') &&
                selected.contains(f['id']),
          )
          .map((f) => f['id'] as String)
          .toList();
      d['requests'] = [
        for (final v in s.reviewRows('requests'))
          if (v.id == id)
            {
              ...v.toJson(),
              'supervisorStatus': decision,
              'ruleSnapshot':
                  v.data['ruleSnapshot'] ?? s.reviewRule(r)?.toJson(),
            }
          else
            v.toJson(),
      ];
      d['feedback'] = [
        for (final f in feedback)
          {...f, if (validIds.contains(f['id'])) 'official': true},
      ];
      final label = '${r.text('documentTitle')} ${r.text('version')}';
      final title = decision == 'approved'
          ? 'Giảng viên phê duyệt $label.'
          : decision == 'needsRevision'
          ? 'Giảng viên yêu cầu chỉnh sửa $label.'
          : 'Giảng viên đánh dấu $label không đạt.';
      d['audit'] = [
        ...s.valuesOfReview('audit'),
        event(
          s,
          id,
          title,
          tone: decision == 'approved'
              ? 'brand'
              : decision == 'needsRevision'
              ? 'rust'
              : 'danger',
          quote: note.trim().isEmpty ? null : '“${note.trim()}”',
          version: r.text('version'),
          selected: validIds,
        ),
      ];
      return withReview(s, d);
    });
    // Ghi quyết định lên bài nộp để "Bài của tôi" đọc được ngay, kể cả khi
    // server chưa có route /notifications/decision (ghi trùng giá trị, idempotent).
    syncSubmissionStatus(
      submissionId,
      (sync) => sync.decided(
        submissionId,
        reviewId: id,
        decision: decision,
        reason: note.trim(),
      ),
    );
    // Bài nộp thật (có submissionId) mới báo server đẩy thông báo cho học viên.
    // Lỗi mạng chỉ ghi log: quyết định đã lưu vẫn giữ nguyên, không bị trả về lỗi.
    if (isMounted && submissionId.isNotEmpty) {
      final notifier = submissionNotifier;
      final reason = note.trim();
      unawaited(() async {
        try {
          final sent = await notifier.notifyStudentDecision(
            submissionId: submissionId,
            decision: decision,
            reason: reason,
          );
          if (!sent) {
            await crashlyticsService.log(
              'Student decision notify not delivered: $submissionId',
            );
          }
        } on Object catch (error, stackTrace) {
          await crashlyticsService.logError(
            error,
            stackTrace,
            reason: 'student_decision_notify_error',
            keys: {'submission_id': submissionId, 'decision': decision},
          );
        }
      }());
    }
    if (isMounted) {
      unawaited(
        analyticsService.logSubmitReviewDecision(
          reviewId: id,
          decision: decision,
        ),
      );
    }
  }

  // Lưu hai bước: loading rồi kết quả; token nhận diện lần chạy, phiên bản giới hạn bản nộp được cập nhật.
  Future<void> runEvaluation(String id, {bool simulateError = false}) async {
    final operationScope = sessionScope;
    operationScope.requireActive();
    if (!activeEvaluationIds.add(id)) {
      throw const AcademicFailure('AI đang xử lý.');
    }
    final token = nextId('eval');
    late String documentTitle;
    late RuleSet activeRule;
    var fileUrl = '';
    var fileName = '';
    var units = <({String criterionId, String section, String text})>[];
    final gateway = simulateError ? null : aiGateway;
    try {
      await mutate((s) {
        final r = writableReview(s, id, ai: true);
        documentTitle = r.text('documentTitle');
        fileUrl = r.text('fileUrl');
        fileName = r.text('fileName');
        final rule = s.reviewRule(r);
        if (rule == null || !rule.active || !rule.flag('aiEnabled')) {
          throw const AcademicFailure(
            'AI chưa được bật trong bộ quy tắc Đang áp dụng.',
          );
        }
        activeRule = rule;
        final invalid = AcademicPolicy.validateRule(rule.toJson());
        if (invalid != null) throw AcademicFailure(invalid);
        final d = reviewData(s);
        final version = s
            .versionsFor(r)
            .where((v) => v.text('version') == r.text('version'))
            .first;
        final run = <String, dynamic>{
          'id': token,
          'reviewId': id,
          'documentId': r.text('documentId', r.text('documentTitle')),
          'documentVersionId': version.id,
          'documentVersion': r.text('version'),
          'ruleSetId': rule.id,
          'ruleSetVersion': rule.version,
          'ruleSnapshot': rule.toJson(),
          'criterionResults': <dynamic>[],
          'overallScore': null,
          'maxScore': 0,
          'findings': <dynamic>[],
          'evaluationStatus': 'loading',
          'createdAt': timestamp(),
        };
        // Bài nộp có tệp thật thì chờ trích văn bản từ tệp; yêu cầu seed giữ nội dung mẫu.
        units = fileUrl.isEmpty
            ? ReviewPolicy.aiUnits(s, AcademicRecord(run), documentTitle)
            : const [];
        // Lần thử mới giữ lịch sử cũ; các bản ghi loading bị gián đoạn được đánh dấu error trước khi thêm lần chạy.
        d['evaluations'] = [
          for (final e in s.reviewRows('evaluations'))
            if (e.text('reviewId') == id &&
                e.text('evaluationStatus') == 'loading')
              {
                ...e.toJson(),
                'evaluationStatus': 'error',
                'error': 'Lần chạy trước bị gián đoạn. Đã tạo lần thử mới.',
              }
            else
              e.toJson(),
          run,
        ];
        if (!s.reviewRows('versions').any((v) => v.id == version.id)) {
          d['versions'] = [...s.valuesOfReview('versions'), version.toJson()];
        }
        d['requests'] = [
          for (final v in s.reviewRows('requests'))
            if (v.id == id)
              {
                ...v.toJson(),
                'ruleSnapshot': rule.toJson(),
                'aiStatus': 'aiReviewing',
              }
            else
              v.toJson(),
        ];
        return withReview(s, d);
      });

      // Có endpoint + Firebase → chấm thật qua FastAPI /review/batch, mỗi tiêu chí một đoạn.
      // Lỗi thì lượt chạy là lỗi (có nút Thử lại), KHÔNG lùi về điểm minh hoạ.
      // Không cấu hình → kết quả minh hoạ, gắn nhãn aiSource: illustration.
      Map<String, AiCriterionScore>? aiScores;
      String? aiModel;
      String? aiError;
      if (gateway != null) {
        // Có tệp nộp thật → trích văn bản từ tệp rồi mới chấm, không dùng documentSamples.
        if (fileUrl.isNotEmpty) {
          final url = Uri.tryParse(fileUrl);
          if (url == null) {
            aiError = 'Đường dẫn tệp nộp không hợp lệ.';
          } else {
            try {
              final extracted = await gateway.extractDocument(
                url: url,
                fileName: fileName,
              );
              units = ReviewPolicy.fileUnits(
                activeRule,
                documentTitle,
                extracted.sections,
              );
            } on AiReviewException catch (e, stackTrace) {
              aiError = e.message;
              if (isMounted) {
                unawaited(
                  crashlyticsService.logError(
                    e,
                    stackTrace,
                    reason: 'ai_review_extract_error',
                    keys: {'review_id': id, 'document_title': documentTitle},
                  ),
                );
              }
            }
          }
        }
        if (aiError != null) {
          // Lỗi trích xuất giữ nguyên nhánh lỗi của lượt chạy; không gọi batch bằng nội dung mẫu.
        } else if (units.isEmpty) {
          aiError = fileUrl.isEmpty
              ? 'Không có nội dung tài liệu để AI đối chiếu.'
              : 'Không trích được nội dung từ tệp nộp để AI đối chiếu.';
        } else {
          try {
            final outcome = await gateway.reviewBatch([
              for (final u in units)
                AiReviewUnit(
                  requirementId: u.criterionId,
                  text: u.text,
                  section: u.section,
                  // Gửi kèm tiêu chí để AI chấm đúng câu hỏi của giảng viên, nhận xét tiếng Việt.
                  criterion: _aiCriterion(activeRule, u.criterionId),
                  outputLanguage: 'vi',
                ),
            ]);
            if (outcome.results.isEmpty) {
              aiError =
                  outcome.failed.values.firstOrNull ??
                  'AI không trả kết quả cho tài liệu này.';
            } else {
              aiScores = {
                for (final e in outcome.results.entries)
                  e.key: AiCriterionScore(
                    score: e.value.score,
                    contextNote: e.value.contextNote,
                    issues: [for (final i in e.value.issues) AcademicRecord(i)],
                  ),
              };
              aiModel = outcome.results.values.first.model;
            }
          } on AiReviewException catch (e, stackTrace) {
            aiError = e.message;
            if (isMounted) {
              unawaited(
                crashlyticsService.logError(
                  e,
                  stackTrace,
                  reason: 'ai_review_live_api_error',
                  keys: {'review_id': id, 'document_title': documentTitle},
                ),
              );
            }
          }
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      final failed = simulateError || aiError != null;

      if (simulateError && isMounted) {
        unawaited(
          crashlyticsService.logError(
            StateError('AI evaluation error on $id'),
            StackTrace.current,
            reason: 'ai_review_evaluation_error',
            keys: {'review_id': id},
          ),
        );
      }

      // Sau thời gian chờ, kiểm tra lại phiên để kết quả trễ không ghi sau khi đăng xuất.
      operationScope.requireActive();
      await mutate((s) {
        final run = s
            .reviewRows('evaluations')
            .where((v) => v.id == token)
            .firstOrNull;
        if (run == null) {
          return s;
        }
        final result = failed
            ? AcademicRecord({
                ...run.toJson(),
                'evaluationStatus': 'error',
                'error':
                    aiError ??
                    'Không thể tạo kết quả. Chọn Thử lại để tiếp tục.',
              })
            : aiScores != null
            ? ReviewPolicy.fromAi(
                s,
                run,
                documentTitle,
                aiScores,
                model: aiModel,
                fromFile: fileUrl.isNotEmpty,
              )
            : ReviewPolicy.illustration(s, run, documentTitle);
        final d = reviewData(s);
        d['evaluations'] = [
          for (final e in s.reviewRows('evaluations'))
            e.id == token ? result.toJson() : e.toJson(),
        ];
        d['requests'] = [
          for (final v in s.reviewRows('requests'))
            // Chỉ cập nhật trạng thái yêu cầu nếu phiên bản vẫn khớp lần AI; kết quả lần chạy được lưu riêng theo token.
            if (v.id == id && v.text('version') == run.text('documentVersion'))
              {
                ...v.toJson(),
                'aiStatus': failed ? 'notRun' : 'aiReviewed',
                'ai': {
                  'errors': result
                      .values('findings')
                      .where((f) => f['level'] == 'error')
                      .length,
                  'warnings': result
                      .values('findings')
                      .where((f) => f['level'] == 'warning')
                      .length,
                  'suggestions': result
                      .values('criterionResults')
                      .fold<int>(
                        0,
                        (n, c) => n + (c['suggestions'] as List).length,
                      ),
                },
              }
            else
              v.toJson(),
        ];
        d['audit'] = [
          ...s.valuesOfReview('audit'),
          event(
            s,
            id,
            'Đánh giá AI ${failed ? 'gặp lỗi' : 'hoàn tất'} · ${run.text('documentVersion')} · ${(run.data['ruleSnapshot'] as Map)['name']} v${run.integer('ruleSetVersion')}',
            tone: failed ? 'rust' : 'olive',
          ),
        ];
        return withReview(s, d);
      });
      if (!failed && isMounted) {
        unawaited(analyticsService.logRunAiReview(id));
      }
    } finally {
      if (operationScope.active) activeEvaluationIds.remove(id);
    }
  }
}

// Đuôi tệp viết hoa để khớp `fileType` của các yêu cầu seed (PDF, DOCX…).
String _fileType(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 || dot == fileName.length - 1
      ? ''
      : fileName.substring(dot + 1).toUpperCase();
}

// Đọc danh sách đánh giá từ dữ liệu cũ; thiếu danh sách thì dùng rỗng để ghép thêm sự kiện mới.
extension ReviewValues on AcademicSnapshot {
  List<dynamic> valuesOfReview(String key) =>
      (data['reviewState'] as Map)[key] as List? ?? [];
}

/// Dòng rubric gửi kèm unit chấm AI; `null` khi id không còn trong bộ quy tắc.
AiReviewCriterion? _aiCriterion(RuleSet rule, String criterionId) {
  final c = rule.criteria.where((c) => c.id == criterionId).firstOrNull;
  if (c == null) return null;
  return AiReviewCriterion(
    id: c.id,
    name: c.name,
    description: c.text('description'),
    evidence: c.text('evidenceRequirement'),
    maxScore: c.maxScore,
  );
}
