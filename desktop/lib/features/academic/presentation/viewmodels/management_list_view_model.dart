import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/core/domain/academic/academic_projections.dart';
import 'package:srs_review_ai/core/session/session_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_view_model.dart';

// Bộ lọc, thẻ chọn và sắp xếp riêng từng danh sách; chế độ xem đã lưu chỉ tồn tại trong phiên.
class ManagementListState {
  const ManagementListState({
    this.q = '',
    this.facets = const {},
    this.tab = 0,
    this.sort = 'Mới nhất',
  });
  final String q, sort;
  final int tab;
  final Map<String, List<String>> facets;
}

// Giữ bộ lọc độc lập theo khóa danh sách hoặc trang chi tiết, làm mới theo phiên đăng nhập.
final managementListProvider =
    NotifierProvider.family<
      ManagementListViewModel,
      ManagementListState,
      String
    >(ManagementListViewModel.new);

// Các nhóm điều kiện kết hợp AND, các giá trị cùng nhóm kết hợp OR.
// Lựa chọn con được giới hạn theo phạm vi cha.
class ManagementListViewModel extends Notifier<ManagementListState> {
  ManagementListViewModel(this.kind);
  int get selectedFacetCount => state.facets.entries
      .where(
        (e) =>
            !['semester', 'from', 'to'].contains(e.key) && e.value.isNotEmpty,
      )
      .length;
  final String kind;
  final Map<String, ManagementListState> saved = {};
  ProjectDocumentProjection projectDocuments(String projectId) {
    final project = snapshot.project(projectId);
    return ProjectDocumentProjection(
      project == null ? [] : snapshot.projectDocuments(project),
      state.tab,
    );
  }

  AcademicSnapshot get snapshot =>
      ref.read(academicViewModelProvider).requireValue;
  @override
  ManagementListState build() {
    ref.watch(sessionScopeProvider);
    // Bỏ chế độ xem của phiên trước; dự án và yêu cầu đánh giá mặc định giới hạn trong học kỳ hiện tại.
    saved.clear();
    return ManagementListState(
      facets: {
        if (['projects', 'reviews', 'documents'].contains(kind))
          'semester': [snapshot.currentSemesterId],
        if (kind == 'projects') 'status': ['active'],
        if (kind == 'reviews') 'status': ['waiting'],
      },
    );
  }

  void tab(int v) => state = ManagementListState(
    q: state.q,
    facets: state.facets,
    sort: state.sort,
    tab: v,
  );
  void query(String q) => state = ManagementListState(
    q: q,
    facets: state.facets,
    sort: state.sort,
    tab: state.tab,
  );
  void sort(String v) => state = ManagementListState(
    q: state.q,
    facets: state.facets,
    sort: v,
    tab: state.tab,
  );
  // Khi áp dụng bộ lọc, loại giá trị con không còn phù hợp với các điều kiện cha đã chọn.
  void apply(Map<String, List<String>> facets) {
    final next = {...facets};
    for (var i = 0; i < hierarchy.length; i++) {
      final key = hierarchy[i];
      final parents = hierarchy.take(i);
      final valid = rows
          .where(
            (r) => parents.every(
              (p) =>
                  next[p]?.isNotEmpty != true || next[p]!.contains(r.text(p)),
            ),
          )
          .map((r) => r.text(key))
          .toSet();
      if (next[key] != null) {
        next[key] = next[key]!.where(valid.contains).toList();
      }
    }
    state = ManagementListState(
      q: state.q,
      facets: next,
      tab: state.tab,
      sort: state.sort,
    );
  }

  void set(String key, List<String> value) =>
      apply({...state.facets, key: value});
  void clear() => state = const ManagementListState();
  void actionable() => state = ManagementListState(
    facets: {
      'semester': [snapshot.currentSemesterId],
      'status': ['waiting'],
    },
  );
  void save(String name) {
    if (name.trim().isNotEmpty) saved[name.trim()] = state;
    state = ManagementListState(
      q: state.q,
      facets: {...state.facets},
      tab: state.tab,
      sort: state.sort,
    );
  }

  String facetTitle(String key) => key == 'status'
      ? kind == 'projects'
            ? 'Trạng thái dự án'
            : kind == 'documents'
            ? 'Tiến độ tài liệu'
            : 'Giảng viên đánh giá'
      : const {
              'semester': 'Học kỳ',
              'course': 'Môn học',
              'class': 'Lớp',
              'lab': 'Lab',
              'labItem': 'Mục Lab',
              'group': 'Nhóm',
              'project': 'Dự án',
              'docType': 'Loại tài liệu',
              'documentStatus': 'Trạng thái tài liệu',
              'evaluationStatus': 'Đánh giá AI',
              'ai': 'Kết quả AI',
              'legacyReviewStatus': 'Trạng thái tổng hợp',
              'time': 'Thời gian',
              'schedule': 'Lịch học',
              'session': 'Buổi',
            }[key] ??
            key;
  List<(String, String, String)> get chips => [
    for (final e in state.facets.entries)
      if (!(['projects', 'reviews'].contains(kind) && e.key == 'semester') &&
          !['from', 'to'].contains(e.key))
        for (final v in e.value)
          (e.key, v, '${facetTitle(e.key)}: ${label(v)}'),
  ];
  String saveCurrent() {
    final name = chips.isEmpty ? 'Tất cả' : chips.map((c) => c.$3).join(' · ');
    save(name);
    return name;
  }

  void toggleFacet(String key, String value) {
    final old = state.facets[key] ?? [];
    set(
      key,
      old.contains(value)
          ? old.where((v) => v != value).toList()
          : [...old, value],
    );
  }

  // Đếm lựa chọn trong phạm vi các điều kiện còn lại và từ khóa; bỏ chính điều kiện đang đếm.
  int facetCount(String key, String value) => rows
      .where(
        (r) =>
            r.text(key) == value &&
            r
                .text('search')
                .toLowerCase()
                .contains(state.q.trim().toLowerCase()) &&
            state.facets.entries
                .where((e) => e.key != key && e.value.isNotEmpty)
                .every(
                  (e) => e.key == 'schedule'
                      ? e.value.any(
                          (v) => v.length == 1
                              ? r.text(e.key).contains(v)
                              : r.text(e.key) == v,
                        )
                      : e.value.contains(r.text(e.key)),
                ),
      )
      .length;

  void restore(String name) {
    if (saved[name] != null) state = saved[name]!;
  }

  static const hierarchy = [
    'semester',
    'course',
    'class',
    'lab',
    'labItem',
    'docType',
    'group',
    'project',
  ];
  List<String> get facetKeys => kind == 'projects'
      ? [
          'semester',
          'course',
          'class',
          'group',
          'status',
          'schedule',
          'session',
        ]
      : [
          'semester',
          'course',
          'class',
          'lab',
          'labItem',
          'group',
          'project',
          'docType',
          'status',
          'documentStatus',
          if (kind != 'documents') ...[
            'evaluationStatus',
            'ai',
            'legacyReviewStatus',
            'time',
            'from',
            'to',
          ],
          'schedule',
          'session',
        ];
  Map<String, String> facetsFor(AcademicRecord p) {
    final s = snapshot;
    final cls = s.projectClass(p);
    return {
      'semester': cls?.semesterId ?? '',
      'course': cls?.courseId ?? '',
      'class': cls?.id ?? '',
      'group': p.text('groupId'),
      'project': p.id,
      'schedule': cls?.schedule ?? '',
      'session': cls?.session ?? '',
    };
  }

  // Ghép dự án, tài liệu hoặc yêu cầu thành cùng cấu trúc để dùng chung bộ lọc học vụ.
  List<AcademicRecord> get rows {
    final s = snapshot;
    if (kind == 'projects') {
      return s
          .records('projects')
          .map(
            (p) => AcademicRecord({
              ...p.toJson(),
              ...facetsFor(p),
              'status': p.text('state'),
              'search':
                  '${p.name} ${s.group(p.text('groupId'))?.name ?? ''} ${p.text('description')}',
            }),
          )
          .toList();
    }
    if (kind == 'documents') {
      return s
          .records('projects')
          .expand(
            (p) => s
                .projectDocuments(p)
                .where(
                  (d) =>
                      d.text('latestVersion').isNotEmpty ||
                      d.text('documentStatus') == 'draft',
                )
                .map(
                  (d) => AcademicRecord({
                    ...d.toJson(),
                    ...facetsFor(p),
                    'docType': d.text('title'),
                    'lab': '${s.projectClass(p)?.id}::${d.text('labCode')}',
                    'labItem':
                        '${s.projectClass(p)?.id}::${d.id}::${d.text('title')}',
                    'status': d.text(
                      'supervisorStatus',
                      d.flag('submissionLocked') &&
                              d.text('documentStatus') != 'notStarted'
                          ? 'locked'
                          : d.text('documentStatus'),
                    ),
                    'search': '${d.text('title')} ${p.name}',
                  }),
                ),
          )
          .toList();
    }
    return s
        .reviewRows('requests')
        .where((r) => kind != 'history' || s.eventsFor(r.id).isNotEmpty)
        .map((r) {
          final cls = s.classRoom(r.text('classId'));
          final labs = cls == null ? <AcademicLab>[] : s.effectiveLabs(cls);
          final lab = labs
              .where(
                (l) => l.items.any(
                  (i) =>
                      i.id == r.text('documentId') ||
                      i.title == r.text('documentTitle'),
                ),
              )
              .firstOrNull;
          final item = lab?.items
              .where(
                (i) =>
                    i.id == r.text('documentId') ||
                    i.title == r.text('documentTitle'),
              )
              .firstOrNull;
          final eval = s.evaluation(r);
          final ai = eval == null
              ? null
              : ReviewPolicy.currentIllustration(
                  s,
                  eval,
                  r.text('documentTitle'),
                );
          final status = r.text('supervisorStatus');
          final aiStatus = eval?.text('evaluationStatus') ?? 'notRun';
          return AcademicRecord({
            ...r.toJson(),
            'semester': r.text('semesterId'),
            'course': r.text('courseId'),
            'class': r.text('classId'),
            'group': r.text('groupId'),
            'project': r.text('projectId'),
            'docType': r.text('documentTitle'),
            'status': status,
            'lab': lab == null ? '' : '${cls?.id}::${lab.code}',
            'labItem':
                '${cls?.id}::${item?.id ?? r.text('documentId')}::${r.text('documentTitle')}',
            'evaluationStatus': aiStatus,
            'ai': aiStatus == 'completed'
                ? ai!.jsonRecords('findings').any((f) => f['level'] == 'error')
                      ? 'hasErrors'
                      : 'clean'
                : aiStatus == 'loading'
                ? 'running'
                : 'notRun',
            // Trạng thái tổng hợp chỉ phục vụ bộ lọc tương thích cũ, không thay quyết định giảng viên hay trạng thái AI.
            'legacyReviewStatus': status == 'waiting'
                ? r.text('documentStatus') == 'resubmitted'
                      ? 'resubmitted'
                      : 'waiting'
                : status == 'inReview'
                ? 'inReview'
                : status == 'needsRevision'
                ? 'needsRevision'
                : 'done',
            'schedule': cls?.schedule ?? '',
            'session': cls?.session ?? '',
            'search':
                '${r.text('projectName')} ${r.text('documentTitle')} ${r.text('submitter')} ${r.text('classCode')} ${r.text('groupName')}',
          });
        })
        .toList();
  }

  // Lọc từ khóa rồi từng điều kiện; lịch sử dùng thời gian sự kiện cuối, yêu cầu dùng requestedTs.
  List<AcademicRecord> get visible {
    final list = rows.where((r) {
      if (!r
          .text('search')
          .toLowerCase()
          .contains(state.q.trim().toLowerCase())) {
        return false;
      }
      for (final e in state.facets.entries) {
        if (e.value.isEmpty) continue;
        final ts = kind == 'history' ? eventTime(r) : r.integer('requestedTs');
        if (e.key == 'time') {
          final range = timeRange(e.value.first);
          if (range != null && (ts < range.$1 || ts > range.$2)) return false;
          continue;
        }
        if (e.key == 'from' || e.key == 'to') {
          final boundary = DateTime.tryParse(e.value.first);
          if (boundary == null) continue;
          if (state.facets['time']?.firstOrNull != 'custom') continue;
          // Giới hạn tùy chọn tính đến hết phút được chọn ở mốc kết thúc.
          if (e.key == 'from' && ts < boundary.millisecondsSinceEpoch ||
              e.key == 'to' && ts > boundary.millisecondsSinceEpoch + 59999) {
            return false;
          }
        } else if (e.key == 'schedule' && e.value.any((v) => v.length == 1)) {
          // Giá trị lịch học một chữ số khớp từng ngày trong mã lịch ghép, như 2 khớp 25.
          if (!e.value.any((v) => r.text('schedule').contains(v))) return false;
        } else if (!e.value.contains(r.text(e.key))) {
          return false;
        }
      }
      return true;
    }).toList();
    if (kind == 'reviews' || kind == 'history') {
      list.sort((a, b) {
        if (kind == 'history') return eventTime(b).compareTo(eventTime(a));
        if (state.sort == 'Cũ nhất') {
          return a.integer('requestedTs').compareTo(b.integer('requestedTs'));
        }
        if (state.sort == 'Chờ lâu nhất') {
          final cmp = (snapshot.completed(a) ? 1 : 0).compareTo(
            snapshot.completed(b) ? 1 : 0,
          );
          return cmp != 0
              ? cmp
              : a.integer('requestedTs').compareTo(b.integer('requestedTs'));
        }
        if (state.sort == 'Hạn nộp gần nhất') {
          return (snapshot.project(a.text('projectId'))?.text('deadline') ??
                  '2099')
              .compareTo(
                snapshot.project(b.text('projectId'))?.text('deadline') ??
                    '2099',
              );
        }
        // Chưa có kết quả AI hoàn tất được xếp sau; ưu tiên số lỗi rồi số cảnh báo, không coi thiếu kết quả là sạch.
        if (state.sort == 'AI có lỗi nhiều nhất') {
          int count(AcademicRecord r, String level) {
            final raw = snapshot.evaluation(r);
            if (raw == null || raw.text('evaluationStatus') != 'completed') {
              return -1;
            }
            return ReviewPolicy.currentIllustration(
              snapshot,
              raw,
              r.text('documentTitle'),
            ).jsonRecords('findings').where((f) => f['level'] == level).length;
          }

          final cmp = count(b, 'error').compareTo(count(a, 'error'));
          return cmp != 0
              ? cmp
              : count(b, 'warning').compareTo(count(a, 'warning'));
        }
        return b.integer('requestedTs').compareTo(a.integer('requestedTs'));
      });
    }
    return list;
  }

  static const timeLabels = {
    'today': 'Hôm nay',
    'yesterday': 'Hôm qua',
    '7d': '7 ngày gần đây',
    '30d': '30 ngày gần đây',
    'thisWeek': 'Tuần này',
    'lastWeek': 'Tuần trước',
    'thisMonth': 'Tháng này',
    'custom': 'Tùy chọn',
  };
  // Tính khoảng lọc theo đồng hồ dữ liệu mẫu; trừ 1 mili giây để mốc cuối thuộc đúng kỳ đã chọn.
  (int, int)? timeRange(String preset) {
    final now = DateTime.fromMillisecondsSinceEpoch(snapshot.integer('now'));
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final pair = switch (preset) {
      'today' => (today, today.add(const Duration(days: 1))),
      'yesterday' => (today.subtract(const Duration(days: 1)), today),
      '7d' => (
        today.subtract(const Duration(days: 6)),
        today.add(const Duration(days: 1)),
      ),
      '30d' => (
        today.subtract(const Duration(days: 29)),
        today.add(const Duration(days: 1)),
      ),
      'thisWeek' => (monday, monday.add(const Duration(days: 7))),
      'lastWeek' => (monday.subtract(const Duration(days: 7)), monday),
      'thisMonth' => (
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 1),
      ),
      _ => null,
    };
    return pair == null
        ? null
        : (pair.$1.millisecondsSinceEpoch, pair.$2.millisecondsSinceEpoch - 1);
  }

  // Đọc thời gian sự kiện cuối theo định dạng hiển thị; không đọc được thì dùng 0 để sắp xếp.
  int eventTime(AcademicRecord r) {
    final time = snapshot.eventsFor(r.id).lastOrNull?.text('time') ?? '';
    final m = RegExp(
      r'(\d{2})/(\d{2})/(\d{4}).*?(\d{2}):(\d{2})',
    ).firstMatch(time);
    return m == null
        ? 0
        : DateTime(
            int.parse(m[3]!),
            int.parse(m[2]!),
            int.parse(m[1]!),
            int.parse(m[4]!),
            int.parse(m[5]!),
          ).millisecondsSinceEpoch;
  }

  // Lựa chọn con chỉ phụ thuộc các cấp cha trong bản nháp bộ lọc, không bị từ khóa thu hẹp.
  Map<String, String> options(String key, Map<String, List<String>> draft) {
    if (key == 'time') return timeLabels;
    if (key == 'schedule') {
      return {
        for (final v in ['25', '36', '47', '2', '3', '4', '5', '6', '7'])
          v: v.length == 1 ? 'T$v' : label(v),
      };
    }
    if (key == 'session') {
      return {'morning': 'Sáng', 'afternoon': 'Chiều', 'evening': 'Tối'};
    }
    final parents = hierarchy.contains(key)
        ? hierarchy.take(hierarchy.indexOf(key))
        : <String>[];
    final values = rows
        .where(
          (r) => parents.every(
            (p) =>
                draft[p]?.isNotEmpty != true || draft[p]!.contains(r.text(p)),
          ),
        )
        .map((r) => r.text(key))
        .where((v) => v.isNotEmpty)
        .toSet();
    if (key == 'status') {
      values.addAll(
        kind == 'projects'
            ? ['active', 'archived']
            : [
                'waiting',
                'inReview',
                'approved',
                'needsRevision',
                'notAccepted',
              ],
      );
    }
    return {for (final v in values) v: label(v)};
  }

  String label(String value) {
    if (timeLabels[value] != null) return timeLabels[value]!;
    final s = snapshot;
    for (final rows in [
      s.semesters,
      s.courses,
      s.classes,
      s.groups,
      s.records('projects'),
    ]) {
      final r = rows.where((r) => r.id == value).firstOrNull;
      if (r != null) {
        return r is ClassRoom
            ? r.code
            : r is Course
            ? r.code
            : r.name;
      }
    }
    if (value.contains('::')) return value.split('::').skip(1).join(' · ');
    return {
          'active': 'Đang thực hiện',
          'archived': 'Đã lưu trữ',
          'waiting': 'Chờ đánh giá',
          'inReview': 'Đang đánh giá',
          'approved': 'Đã phê duyệt',
          'needsRevision': 'Cần chỉnh sửa',
          'notAccepted': 'Không đạt',
          'submitted': 'Đã nộp',
          'resubmitted': 'Đã nộp lại',
          'notStarted': 'Chưa bắt đầu',
          'draft': 'Bản nháp',
          'locked': 'Khóa gửi đánh giá',
          'notRun': 'Chưa chạy',
          'completed': 'Đã có đề xuất',
          'loading': 'Đang xử lý',
          'error': 'Có lỗi',
          'hasErrors': 'Có lỗi AI',
          'clean': 'Không phát hiện lỗi',
          'running': 'AI đang chạy',
          'done': 'Đã hoàn tất',
          '25': 'T2 – T5',
          '36': 'T3 – T6',
          '47': 'T4 – T7',
          'morning': 'Sáng',
          'afternoon': 'Chiều',
          'evening': 'Tối',
        }[value] ??
        value;
  }
}
