import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/parsing/requirement_splitter.dart';

void main() {
  const splitter = RequirementSplitter();

  test('extracts ids and normalises them to two digits', () {
    final items = splitter.split([
      '''
3.2 Functional Requirements
FR-1 The system shall allow a student to upload an SRS file.
FR-02 The system shall display the parsed requirement list.
''',
    ]);

    expect(items.map((i) => i.id), ['FR-01', 'FR-02']);
    expect(items.first.section, '3.2');
    expect(items.first.kind, RequirementKind.functional);
  });

  test('joins continuation lines into one requirement', () {
    final items = splitter.split([
      '''
FR-03 The system shall notify the supervisor
when a new review is completed.
''',
    ]);

    expect(items, hasLength(1));
    expect(
      items.single.text,
      contains('notify the supervisor when a new review'),
    );
  });

  test('classifies UC ids as use cases', () {
    final items = splitter.split([
      '''
UC-07 Submit report
FR-04 The system shall export a PDF.
''',
    ]);

    expect(items.firstWhere((i) => i.id == 'UC-07').isUseCase, isTrue);
    expect(items.firstWhere((i) => i.id == 'FR-04').isUseCase, isFalse);
  });

  test('skips table-of-contents lines and keeps the body wording', () {
    final items = splitter.split([
      '''
FR-01 Upload SRS ....................... 12
FR-01 The system shall let the student upload an SRS document.
''',
    ]);

    expect(items, hasLength(1));
    expect(items.single.text, contains('upload an SRS document'));
  });

  test('picks up modal sentences without an explicit id', () {
    final items = splitter.split([
      'The system must keep an audit log of every review.',
    ]);

    expect(items, hasLength(1));
    expect(items.single.kind, RequirementKind.statement);
  });

  test('recognises Vietnamese modal phrasing', () {
    final items = splitter.split([
      'Hệ thống phải cho phép sinh viên tải lên tài liệu SRS.',
    ]);

    expect(items, hasLength(1));
    expect(items.single.kind, RequirementKind.statement);
  });

  test('reads use case rows out of a use case table', () {
    final items = splitter.split(['Use case name: Submit weekly report']);

    expect(items.single.isUseCase, isTrue);
    expect(items.single.text, 'Submit weekly report');
  });

  test('records the page index of every item', () {
    final items = splitter.split([
      'FR-01 The system shall do the first thing.',
      'FR-02 The system shall do the second thing.',
    ]);

    expect(items[0].pageIndex, 0);
    expect(items[1].pageIndex, 1);
  });

  test('returns nothing for prose without requirements', () {
    expect(
      splitter.split(['This chapter introduces the project background.']),
      isEmpty,
    );
  });

  // Regression: a real FPTU capstone SRS (OTES, 2020) uses a two-page
  // use-case table per use case — Actor/Summary/Goal/.../Main success
  // scenario/Exceptions/Business Rules. The id ("UC01") lands on the first
  // page and the scenario table lands on the second. Flushing the buffer at
  // the end of every page (the original implementation) dropped 80-97% of
  // real use-case text across that document because the id's own page never
  // contains the scenario table. Verified with `pdftotext -f N -l N` against
  // the real PDF before writing this test.
  test('keeps a use case whole when its table spans two PDF pages', () {
    final items = splitter.split([
      '''
USE CASE – UC01
Use Case No.
UC01
Use Case Name
Login
Preconditions:
''',
      '''
N/A.
Main success scenario:
Step
Actor Action
System Response
1
User goes to the login view.
The system sends a login command to Google.
2
User inputs information.
3
User sends command to login to system
''',
    ]);

    final uc01 = items.single;
    expect(uc01.id, 'UC-01');
    // The starting page, not the page the table happens to finish on — so
    // "jump to page" still lands where the use case begins.
    expect(uc01.pageIndex, 0);
    expect(uc01.text, contains('Login'));
    expect(uc01.text, contains('User goes to the login view'));
    expect(uc01.text, contains('User sends command to login to system'));
  });

  test('a bare Figure/Table caption line closes the current item instead of '
      'being absorbed into it', () {
    final items = splitter.split([
      '''
UC01 Login
Some use case body text.
Table 9.
Figure 3.
2.3.2 Next Section Heading
UC02 Raise hand
''',
    ]);

    expect(items.map((i) => i.id), ['UC-01', 'UC-02']);
    expect(items.first.text, isNot(contains('Figure 3')));
    expect(items.first.text, isNot(contains('Table 9')));
  });

  // Regression: a real VN capstone SRS ("ĐẶC TẢ YÊU CẦU PHẦN MỀM (SRS).pdf")
  // codes functional requirements as `F-01: Trang Chủ`, `F-02: …`. The old
  // prefix set (FR|NFR|UC|BR|SR) matched none of them and the file parsed to
  // 0 units. Single-letter ids must keep the dash: bare `F01`/`F 1` would hit
  // ordinary prose like "F 1 triệu đồng".
  test('recognises single-letter F- ids from a real Vietnamese SRS', () {
    final items = splitter.split([
      '''
3.1. PHÂN HỆ KHÁCH XEM (USER PAGE) - FRONTEND
F-01: Trang Chủ
   - Mô tả: Màn hình chính người dùng tiếp cận đầu tiên.
   - Quy tắc xử lý: Header chuyển sang nền mờ khi cuộn trang.
F-02: Trang Dịch Vụ
   - Mô tả: Danh sách dịch vụ của doanh nghiệp.
''',
    ]);

    expect(items.map((i) => i.id), ['F-01', 'F-02']);
    expect(items.first.kind, RequirementKind.functional);
    expect(items.first.section, '3.1');
    expect(items.first.text, contains('Màn hình chính'));
    expect(items.first.text, contains('nền mờ khi cuộn trang'));
  });

  test('recognises NF- ids and keeps the dash-only rule for F', () {
    final withNf = splitter.split(['NF-02 Hệ thống phải phản hồi trong 2s.']);
    expect(withNf.single.id, 'NF-02');

    // No dash -> not an id; the line must not be swallowed as a requirement.
    final withoutDash = splitter.split([
      'F01 This looks like prose, not a requirement id.',
    ]);
    expect(withoutDash, isEmpty);
  });

  test('preserves every explicit occurrence, including repeated ids', () {
    final items = splitter.split([
      'UC04 First workflow.',
      'UC04 Second workflow.',
      'UC-04 Third workflow.',
    ]);

    expect(items.map((item) => item.id), ['UC-04', 'UC-04', 'UC-04']);
    expect(items.map((item) => item.text), [
      'First workflow.',
      'Second workflow.',
      'Third workflow.',
    ]);
  });

  test('keeps malformed four-digit ids visible instead of dropping them', () {
    final items = splitter.split([
      'UC0114 Legacy workflow.',
      'UC0134 Another legacy workflow.',
    ]);

    expect(items.map((item) => item.id), ['UC0114', 'UC0134']);
    expect(items.every((item) => item.isUseCase), isTrue);
  });

  test(
    'keeps modal fallback statements when no explicit scope signal exists',
    () {
      final items = splitter.split([
        'Appendix notes',
        'The system must retain the audit trail.',
      ]);

      expect(items, hasLength(1));
      expect(items.single.id, 'ST-1');
      expect(items.single.kind, RequirementKind.statement);
      expect(items.single.section, isNull);
    },
  );
}
