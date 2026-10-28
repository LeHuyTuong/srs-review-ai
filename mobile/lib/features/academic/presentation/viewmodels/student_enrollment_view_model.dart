import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';

// Bản nháp ghi danh tách theo lớp và bị tạo lại khi phiên đổi, tránh trộn danh sách đang chọn.
final studentEnrollmentProvider = NotifierProvider.autoDispose
    .family<StudentEnrollmentViewModel, EnrollmentState, String>(
      StudentEnrollmentViewModel.new,
    );

// Bản nháp thêm sinh viên; hủy bảng nhập không ghi danh hoặc thay đổi danh sách lớp.
class EnrollmentState {
  const EnrollmentState({
    this.tab = 0,
    this.q = '',
    this.selected = const {},
    this.rows = const [],
    this.fileName = '',
    this.error = '',
    this.busy = false,
  });
  final int tab;
  final String q, fileName, error;
  final Set<String> selected;
  final List<AcademicJson> rows;
  final bool busy;
  EnrollmentState copy({
    int? tab,
    String? q,
    Set<String>? selected,
    List<AcademicJson>? rows,
    String? fileName,
    String error = '',
    bool? busy,
  }) => EnrollmentState(
    tab: tab ?? this.tab,
    q: q ?? this.q,
    selected: selected ?? this.selected,
    rows: rows ?? this.rows,
    fileName: fileName ?? this.fileName,
    error: error,
    busy: busy ?? this.busy,
  );
}

// Đọc, kiểm tra CSV và chọn sinh viên từ danh bạ; ghi danh sách qua kho học vụ.
class StudentEnrollmentViewModel extends Notifier<EnrollmentState> {
  StudentEnrollmentViewModel(this.classId);
  final String classId;
  int get validRowCount =>
      state.rows.where((r) => r['status'] == 'valid').length;
  int get existingRowCount =>
      state.rows.where((r) => r['status'] == 'exists').length;
  int get invalidRowCount => state.rows
      .where((r) => !['valid', 'exists'].contains(r['status']))
      .length;
  AcademicSnapshot get snapshot =>
      ref.read(academicViewModelProvider).requireValue;
  @override
  EnrollmentState build() {
    ref.watch(sessionScopeProvider);
    return const EnrollmentState();
  }

  void tab(int value) => state = state.copy(tab: value);
  void query(String value) => state = state.copy(q: value);
  void select(String id) {
    final selected = {...state.selected};
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    state = state.copy(selected: selected);
  }

  // Bỏ sinh viên đã có trong lớp theo mã, tìm trong danh bạ và chỉ hiển thị tối đa 8 kết quả.
  List<AcademicRecord> get candidates {
    final codes = snapshot
        .classStudents(classId)
        .map((s) => s.studentCode)
        .toSet();
    return snapshot
        .records('directoryStudents')
        .where(
          (s) =>
              !codes.contains(s.text('studentCode')) &&
              '${s.name} ${s.text('studentCode')} ${s.text('email')}'
                  .toLowerCase()
                  .contains(state.q.toLowerCase()),
        )
        .take(8)
        .toList();
  }

  // Phân loại thiếu trường, sai định dạng và trùng mã; tập mã gồm sinh viên trong lớp và các dòng đã đọc.
  List<AcademicJson> validate(List<AcademicJson> rows) {
    final seen = snapshot
        .classStudents(classId)
        .map((s) => s.studentCode)
        .toSet();
    return rows.map((r) {
      final code = r['studentCode']?.toString().trim().toUpperCase() ?? '';
      final name = r['name']?.toString().trim() ?? '';
      final email = r['email']?.toString().trim() ?? '';
      final status = code.isEmpty || name.isEmpty || email.isEmpty
          ? 'missing'
          : !RegExp(r'^[A-Z]{2}\d{6}$').hasMatch(code) || !email.contains('@')
          ? 'format'
          : seen.contains(code)
          ? 'exists'
          : 'valid';
      seen.add(code);
      return {
        'studentCode': code,
        'name': name,
        'email': email,
        'status': status,
      };
    }).toList();
  }

  // Bỏ dòng trống và tiêu đề nhận diện theo mã; đọc tối đa 500 dòng với dấu phẩy, chấm phẩy hoặc tab.
  // Cách tách hiện tại không xử lý trường CSV có dấu phân cách nằm trong dấu nháy.
  void loadCsv(String csv, String name) {
    var lines = csv
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isNotEmpty &&
        RegExp(r'mã|code', caseSensitive: false).hasMatch(lines.first)) {
      lines = lines.skip(1).toList();
    }
    state = state.copy(
      fileName: name,
      rows: validate(
        lines.take(500).map((l) {
          final parts = l
              .split(RegExp(r'[,;\t]'))
              .map((v) => v.trim())
              .toList();
          return {
            'studentCode': parts.firstOrNull ?? '',
            'name': parts.length > 1 ? parts[1] : '',
            'email': parts.length > 2 ? parts[2] : '',
          };
        }).toList(),
      ),
    );
  }

  // Với XLSX chỉ xem trước dữ liệu mẫu; chưa đọc nội dung bảng tính thật.
  void sample([String name = 'danh-sach-SE1701.xlsx']) => state = state.copy(
    fileName: name,
    rows: validate([
      ...snapshot.records('studentImportSample').map((r) => r.toJson()),
      ...snapshot.classStudents(classId).take(2).map((s) => s.toJson()),
    ]),
  );
  // Sau khi chọn tệp, chỉ nhận kết quả nếu màn nhập còn tồn tại và phiên ban đầu chưa bị đóng.
  Future<void> pick() async {
    final scope = ref.read(sessionScopeProvider);
    try {
      final file = await ref.read(studentImportServiceProvider).pick();
      if (!ref.mounted || !scope.active || file == null) return;
      file.csv == null ? sample(file.name) : loadCsv(file.csv!, file.name);
    } catch (e) {
      if (ref.mounted && scope.active) {
        state = state.copy(error: 'Không đọc được tệp. Chọn lại CSV UTF-8.');
      }
    }
  }

  Future<void> copy(String value) =>
      ref.read(studentImportServiceProvider).copy(value);
  Future<void> regenerate() =>
      ref.read(academicViewModelProvider.notifier).regenerateQr(classId);
  // Chỉ gửi dòng xem trước hợp lệ hoặc sinh viên đã chọn; chặn gửi lặp và giữ lỗi để người dùng thử lại.
  Future<bool> save() async {
    final scope = ref.read(sessionScopeProvider);
    if (state.busy) return false;
    state = state.copy(busy: true);
    try {
      final rows = state.tab == 1
          ? state.rows.where((r) => r['status'] == 'valid').toList()
          : snapshot
                .records('directoryStudents')
                .where(
                  (r) => state.selected.contains(
                    r.id.isEmpty ? r.text('studentCode') : r.id,
                  ),
                )
                .map((r) => r.toJson())
                .toList();
      if (rows.isEmpty) {
        throw const AcademicFailure('Chọn sinh viên hợp lệ trước khi thêm.');
      }
      await ref
          .read(academicViewModelProvider.notifier)
          .enrollStudents(classId, rows);
      if (ref.mounted && scope.active) state = state.copy(busy: false);
      return scope.active;
    } catch (e) {
      if (ref.mounted && scope.active) {
        state = state.copy(
          busy: false,
          error: e is AcademicFailure
              ? e.message
              : 'Không thể thêm sinh viên. Vui lòng thử lại.',
        );
      }
      return false;
    }
  }
}
