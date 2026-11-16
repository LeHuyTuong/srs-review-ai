// Kiểm thử tự động cho các luật BR chưa có ca (docs/workflow/business-rules.md):
// BR-01-02, BR-01-04, BR-02-03, BR-02-04, BR-02-06, BR-02-07, BR-02-18.
//
// Mọi id/nhãn/thông điệp ở đây đều có thật: id lấy từ
// `assets/fixtures/academic.json`, thông điệp chép nguyên văn từ code (số dòng
// ghi kèm từng nhóm test). Không bịa dữ liệu mới, chỉ sửa bản chụp trong RAM.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/student_file_picker_service.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';

import 'support/academic_fixture.dart';

// Dự án lưu trữ có sẵn trong seed (group SE1701 Group 07).
const _archivedProject = 'event-management-system';

// Nhóm đã có dự án trong seed: Group 01 → Smart Campus Management.
const _ownedGroup = 'se1701-group-01';

// Ba trạng thái cuối theo BR-02-18, mỗi trạng thái một yêu cầu seed.
const _finalStates = {
  'review-003': 'approved',
  'review-009': 'needsRevision',
  'review-010': 'notAccepted',
};

// Yêu cầu lớp SE1801 (SRS) thuộc bộ quy tắc swr-requirements-2026: bắt buộc AI,
// và seed KHÔNG có bản ghi evaluation nào cho nó.
const _ruleBoundReview = 'review-012';

const _completedMessage = 'Đánh giá đã hoàn tất; lịch sử được giữ nguyên.';
const _oneProjectMessage = 'Nhóm đã có dự án.';
const _archivedMessage = 'Dự án đã lưu trữ, chỉ được xem.';
const _noRuleMessage =
    'Cần gán một bộ quy tắc Đang áp dụng trước khi đánh giá.';
const _aiRequiredMessage =
    'Bộ quy tắc yêu cầu hoàn tất Đánh giá AI trước khi giảng viên bắt đầu đánh giá hoặc ra quyết định.';

/// [PlatformFile] của file_picker là `abstract base class`; implementation thật
/// cần plugin native nên test tự dựng một bản tối thiểu, chỉ đủ cho seam
/// `StudentFileDialog` của [StudentFilePickerService].
final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this.name, {this.bytes, this.size});

  @override
  final String name;

  final Uint8List? bytes;
  final int? size;

  @override
  Uri get uri => Uri.file(p.join('/tmp/srs-test', name));

  @override
  int? lengthSync() => size ?? bytes?.length;

  @override
  Future<int> length() async => lengthSync() ?? 0;

  @override
  Future<Uint8List> readAsBytes() async => bytes ?? Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield await readAsBytes();
  }

  // Dịch vụ chấm điểm không đi qua XFile; cố tình nổ nếu ai đó gọi tới.
  @override
  Never get xFile =>
      throw UnimplementedError('xFile không dùng trong test này');
}

Matcher _failsWith(String message) => throwsA(
  isA<AcademicFailure>().having((e) => e.message, 'message', message),
);

void main() {
  group('BR-01-02 · mỗi nhóm có tối đa một dự án '
      '(management_actions.dart:156)', () {
    late TestAcademicRepository repo;
    late ProviderContainer container;
    late AcademicViewModel vm;

    setUp(() async {
      repo = TestAcademicRepository(academicFixture());
      container = ProviderContainer(
        overrides: [academicRepositoryProvider.overrideWithValue(repo)],
      );
      await container.read(academicViewModelProvider.future);
      vm = container.read(academicViewModelProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('seed: nhóm của dự án Smart Campus Management đang có dự án', () {
      expect(
        repo.snapshot.project('smart-campus-management')!.text('groupId'),
        _ownedGroup,
      );
      expect(repo.snapshot.group(_ownedGroup)!.projectId, isNotEmpty);
    });

    test('tạo dự án thứ hai bị chặn, không ghi bản chụp', () async {
      final before = jsonEncode(repo.snapshot.toJson());
      await expectLater(
        vm.saveProject({
          'groupId': _ownedGroup,
          'name': 'Dự án thứ hai của nhóm',
          'description': '',
          'startDate': '2026-09-01',
          'deadline': '2026-12-15T23:59',
        }),
        _failsWith(_oneProjectMessage),
      );
      expect(jsonEncode(repo.snapshot.toJson()), before);
    });
  });

  group(
    'BR-01-04 · dự án đã lưu trữ chỉ được xem (management_actions.dart:138)',
    () {
      late TestAcademicRepository repo;
      late ProviderContainer container;
      late AcademicViewModel vm;

      setUp(() async {
        repo = TestAcademicRepository(academicFixture());
        container = ProviderContainer(
          overrides: [academicRepositoryProvider.overrideWithValue(repo)],
        );
        await container.read(academicViewModelProvider.future);
        vm = container.read(academicViewModelProvider.notifier);
      });
      tearDown(() => container.dispose());

      test('seed: Event Management System ở trạng thái archived', () {
        expect(
          repo.snapshot.project(_archivedProject)!.text('state'),
          'archived',
        );
      });

      test('lưu lại dự án đã lưu trữ bị chặn, dữ liệu không đổi', () async {
        final before = jsonEncode(repo.snapshot.toJson());
        await expectLater(
          vm.saveProject({
            'id': _archivedProject,
            'groupId': 'se1701-group-07',
            'name': 'Event Management System',
            'description': 'Sửa dự án đã lưu trữ',
            'startDate': '2026-09-01',
            'deadline': '2026-12-15T23:59',
          }),
          _failsWith(_archivedMessage),
        );
        expect(jsonEncode(repo.snapshot.toJson()), before);
      });
    },
  );

  group(
    'BR-02-03 / BR-02-04 · chọn tệp SRS (student_file_picker_service.dart)',
    () {
      test('chỉ đưa pdf/docx/md cho hộp chọn tệp và nhận tệp hợp lệ', () async {
        List<String>? handedToDialog;
        final service = StudentFilePickerService(
          picker: (allowed) async {
            handedToDialog = allowed;
            return _FakePlatformFile(
              'SRS-OTES.md',
              bytes: Uint8List.fromList(const [35, 32, 83, 82, 83]),
              size: 5,
            );
          },
        );
        final picked = await service.pickSrsFile(
          maxSizeBytes: 30 * 1024 * 1024,
          // '.exe' bị lọc khỏi danh sách trước khi mở hộp chọn tệp.
          allowedExtensions: const ['pdf', 'docx', 'md', 'exe'],
        );
        expect(handedToDialog, ['pdf', 'docx', 'md']);
        expect(picked, isNotNull);
        expect(picked!.fileName, 'SRS-OTES.md');
        expect(picked.extension, 'md');
        expect(picked.sizeBytes, 5);
      });

      test('tệp .exe bị từ chối với thông điệp nguyên văn', () async {
        final service = StudentFilePickerService(
          picker: (_) async => _FakePlatformFile(
            'SRS.exe',
            bytes: Uint8List.fromList(const [0x4d, 0x5a]),
            size: 2,
          ),
        );
        await expectLater(
          service.pickSrsFile(
            maxSizeBytes: 30 * 1024 * 1024,
            allowedExtensions: const ['pdf', 'docx', 'md'],
          ),
          throwsA(
            isA<StudentFileException>().having(
              (e) => e.message,
              'message',
              'Chỉ hỗ trợ tệp PDF, DOCX, MD.',
            ),
          ),
        );
      });

      test('tệp rỗng bị từ chối với thông điệp nguyên văn', () async {
        final service = StudentFilePickerService(
          picker: (_) async =>
              _FakePlatformFile('SRS-rong.pdf', bytes: Uint8List(0), size: 0),
        );
        await expectLater(
          service.pickSrsFile(
            maxSizeBytes: 30 * 1024 * 1024,
            allowedExtensions: const ['pdf', 'docx', 'md'],
          ),
          throwsA(
            isA<StudentFileException>().having(
              (e) => e.message,
              'message',
              'Tệp rỗng hoặc không thể đọc.',
            ),
          ),
        );
      });
    },
  );

  group(
    'BR-02-06 / BR-02-07 · supervisorBlock (management_queries.dart:147,151)',
    () {
      late TestAcademicRepository repo;
      late ProviderContainer container;
      late AcademicViewModel vm;

      setUp(() async {
        repo = TestAcademicRepository(academicFixture());
        container = ProviderContainer(
          overrides: [academicRepositoryProvider.overrideWithValue(repo)],
        );
        await container.read(academicViewModelProvider.future);
        vm = container.read(academicViewModelProvider.notifier);
      });
      tearDown(() => container.dispose());

      test(
        'BR-02-06 · không còn bộ quy tắc Đang áp dụng thì chặn đánh giá',
        () async {
          // Bỏ Rule Set của lớp SE1801 khỏi bản chụp: mô phỏng lớp chưa gán bộ quy tắc.
          await vm.mutate(
            (s) => s.replaceCollection(
              'ruleSets',
              s.rules
                  .where((r) => r.id != 'swr-requirements-2026')
                  .map((r) => r.toJson())
                  .toList(),
            ),
          );
          final review = repo.snapshot.review(_ruleBoundReview)!;
          expect(repo.snapshot.reviewRule(review), isNull);
          expect(repo.snapshot.supervisorBlock(review), _noRuleMessage);

          final before = jsonEncode(repo.snapshot.toJson());
          await expectLater(
            vm.startReview(_ruleBoundReview),
            _failsWith(_noRuleMessage),
          );
          await expectLater(
            vm.decideReview(_ruleBoundReview, 'approved'),
            _failsWith(_noRuleMessage),
          );
          expect(jsonEncode(repo.snapshot.toJson()), before);
          expect(
            repo.snapshot.review(_ruleBoundReview)!.text('supervisorStatus'),
            'waiting',
          );
        },
      );

      test(
        'BR-02-07 · bộ quy tắc bắt buộc AI mà chưa có kết quả AI thì chặn',
        () async {
          final review = repo.snapshot.review(_ruleBoundReview)!;
          expect(review.text('classId'), 'se1801');
          expect(repo.snapshot.reviewRule(review)!.id, 'swr-requirements-2026');
          expect(
            repo.snapshot
                .reviewRule(review)!
                .flag('aiRequiredBeforeSupervisor'),
            isTrue,
          );
          // Seed chưa có bản ghi evaluation cho yêu cầu này.
          expect(repo.snapshot.evaluation(review), isNull);
          expect(repo.snapshot.supervisorBlock(review), _aiRequiredMessage);

          final before = jsonEncode(repo.snapshot.toJson());
          await expectLater(
            vm.startReview(_ruleBoundReview),
            _failsWith(_aiRequiredMessage),
          );
          expect(jsonEncode(repo.snapshot.toJson()), before);
          expect(
            repo.snapshot.review(_ruleBoundReview)!.text('supervisorStatus'),
            'waiting',
          );
        },
      );
    },
  );

  group(
    'BR-02-18 · trạng thái cuối không đổi được (review_actions.dart:44-47)',
    () {
      late TestAcademicRepository repo;
      late ProviderContainer container;
      late AcademicViewModel vm;

      setUp(() async {
        repo = TestAcademicRepository(academicFixture());
        container = ProviderContainer(
          overrides: [academicRepositoryProvider.overrideWithValue(repo)],
        );
        await container.read(academicViewModelProvider.future);
        vm = container.read(academicViewModelProvider.notifier);
      });
      tearDown(() => container.dispose());

      test('seed có đủ approved / needsRevision / notAccepted', () {
        for (final entry in _finalStates.entries) {
          expect(
            repo.snapshot.review(entry.key)!.text('supervisorStatus'),
            entry.value,
          );
          expect(
            repo.snapshot.completed(repo.snapshot.review(entry.key)!),
            isTrue,
          );
        }
      });

      for (final entry in _finalStates.entries) {
        test('${entry.value}: startReview/addFeedback/decideReview đều bị chặn '
            'và dữ liệu không đổi', () async {
          final id = entry.key;
          final statusBefore = repo.snapshot
              .review(id)!
              .text('supervisorStatus');
          final eventsBefore = repo.snapshot.eventsFor(id).length;
          final feedbackBefore = repo.snapshot.feedbackFor(id).length;
          final before = jsonEncode(repo.snapshot.toJson());

          await expectLater(vm.startReview(id), _failsWith(_completedMessage));
          await expectLater(
            vm.addFeedback(id, {'message': 'Thử thêm phản hồi sau quyết định'}),
            _failsWith(_completedMessage),
          );
          await expectLater(
            vm.decideReview(id, 'approved'),
            _failsWith(_completedMessage),
          );

          expect(jsonEncode(repo.snapshot.toJson()), before);
          expect(
            repo.snapshot.review(id)!.text('supervisorStatus'),
            statusBefore,
          );
          expect(repo.snapshot.eventsFor(id).length, eventsBefore);
          expect(repo.snapshot.feedbackFor(id).length, feedbackBefore);
        });
      }
    },
  );
}
