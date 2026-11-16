part of 'academic_view_model.dart';

// Lượt đánh giá, phản hồi và nhật ký được lưu cùng bản chụp mô phỏng có kiểm tra revision.
extension ReviewActions on AcademicViewModel {
  AcademicJson reviewData(AcademicSnapshot s) =>
      AcademicRecord(s.data['reviewState'] as AcademicJson).toJson();
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

  // Chỉ chuyển waiting sang inReview; chụp Rule Set nếu chưa có và ghi sự kiện bắt đầu cùng lần lưu.
  Future<void> startReview(String id) => mutate((s) {
    final r = writableReview(s, id);
    if (r.text('supervisorStatus') != 'waiting') return s;
    final d = reviewData(s);
    d['requests'] = [
      for (final v in s.reviewRows('requests'))
        if (v.id == id)
          {
            ...v.toJson(),
            'supervisorStatus': 'inReview',
            'ruleSnapshot': v.data['ruleSnapshot'] ?? s.reviewRule(r)?.toJson(),
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

  // Thêm phản hồi nháp theo phiên bản hiện tại; nếu đang waiting thì đồng thời bắt đầu đánh giá.
  Future<void> addFeedback(String id, AcademicJson input) => mutate((s) {
    final r = writableReview(s, id);
    final message = input['message']?.toString().trim() ?? '';
    if (message.isEmpty) throw const AcademicFailure('Nhập nội dung phản hồi.');
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
        'category': input['category'] ?? s.strings('feedbackCategories').first,
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
  }) => mutate((s) {
    final r = writableReview(s, id);
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
            'ruleSnapshot': v.data['ruleSnapshot'] ?? s.reviewRule(r)?.toJson(),
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

  // Lưu hai bước: loading rồi kết quả; token nhận diện lần chạy, phiên bản giới hạn bản nộp được cập nhật.
  Future<void> runEvaluation(String id, {bool simulateError = false}) async {
    final operationScope = sessionScope;
    operationScope.requireActive();
    if (!activeEvaluationIds.add(id)) {
      throw const AcademicFailure('AI đang xử lý.');
    }
    final token = nextId('eval');
    late String documentTitle;
    try {
      await mutate((s) {
        final r = writableReview(s, id, ai: true);
        documentTitle = r.text('documentTitle');
        final rule = s.reviewRule(r);
        if (rule == null || !rule.active || !rule.flag('aiEnabled')) {
          throw const AcademicFailure(
            'AI chưa được bật trong bộ quy tắc Đang áp dụng.',
          );
        }
        final invalid = AcademicPolicy.validateRule(rule.toJson());
        if (invalid != null) throw AcademicFailure(invalid);
        final d = reviewData(s);
        final version = s
            .versionsFor(r)
            .where((v) => v.text('version') == r.text('version'))
            .first;
        final run = {
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
      await Future<void>.delayed(const Duration(milliseconds: 1200));
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
        final result = simulateError
            ? AcademicRecord({
                ...run.toJson(),
                'evaluationStatus': 'error',
                'error': 'Không thể tạo kết quả. Chọn Thử lại để tiếp tục.',
              })
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
                'aiStatus': simulateError ? 'notRun' : 'aiReviewed',
                'ai': {
                  'errors': result
                      .jsonRecords('findings')
                      .where((f) => f['level'] == 'error')
                      .length,
                  'warnings': result
                      .jsonRecords('findings')
                      .where((f) => f['level'] == 'warning')
                      .length,
                  'suggestions': result
                      .jsonRecords('criterionResults')
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
            'Đánh giá AI ${simulateError ? 'gặp lỗi' : 'hoàn tất'} · ${run.text('documentVersion')} · ${(run.data['ruleSnapshot'] as Map)['name']} v${run.integer('ruleSetVersion')}',
            tone: simulateError ? 'rust' : 'olive',
          ),
        ];
        return withReview(s, d);
      });
    } finally {
      if (operationScope.active) activeEvaluationIds.remove(id);
    }
  }
}

// Đọc danh sách đánh giá từ dữ liệu cũ; thiếu danh sách thì dùng rỗng để ghép thêm sự kiện mới.
extension ReviewValues on AcademicSnapshot {
  List<dynamic> valuesOfReview(String key) =>
      (data['reviewState'] as Map)[key] as List? ?? [];
}
