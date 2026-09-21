import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/parsing/requirement_splitter.dart';

void main() {
  const splitter = RequirementSplitter();

  test('keeps the digits the document wrote for every id', () {
    // Parser 1.2.0 deliberately stopped padding: `FR-1` is the code the
    // student wrote, and rewriting it to `FR-01` made the report quote an id
    // that appears nowhere in their file (see `_canonicalId`).
    final items = splitter.split([
      '''
3.2 Functional Requirements
FR-1 The system shall allow a student to upload an SRS file.
FR-02 The system shall display the parsed requirement list.
''',
    ]);

    expect(items.map((i) => i.id), ['FR-1', 'FR-02']);
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

  test('a DOCX table cell holding only a modal verb never becomes a unit', () {
    // Real OTES failure: a table cell contains just "must", text extraction
    // puts it alone on a line, and the inventory grew a unit whose entire
    // text was "must" — meaningless to review and confusing in the source
    // sheet. A one-word modal fragment is not a requirement statement.
    final items = splitter.split([
      'Preconditions',
      'must',
      'must not',
      'User account',
      'The system must lock the account after five failed attempts.',
    ]);

    expect(items, hasLength(1));
    expect(items.single.id, 'ST-1');
    expect(
      items.single.text,
      'The system must lock the account after five failed attempts.',
    );
  });

  test('a trusted TOC still keeps the FR/NFR prose the body carries', () {
    // The index only declares use-case tables (the capstone "List of use
    // case"), so a TOC-only inventory was ALL use cases — the functional
    // requirements in prose silently went unreviewed. Regression for 1.3.0:
    // the body scan supplements the TOC.
    final pages = [
      // page 0 — index: chapter + three table entries (>= 3 => a TOC page)
      'A.\tIntroduction\t2\n'
          'C.\tSoftware Requirement Specification\t3\n'
          'Table 40. USE CASE - Save student video\t3\n'
          'Table 41. USE CASE - Restore student video\t3\n'
          'Table 42. USE CASE - Rewind student video\t4',
      // page 1 — front matter prose
      'Some introduction prose.',
      // page 2 — the SRS chapter opens with functional requirements...
      'C. Software Requirement Specification\n'
          'FR-1 The system shall let a student upload an SRS file.\n'
          'The system shall validate the file before parsing.',
      // page 3 — ...then the first declared use-case table
      'Table 40. USE CASE - Save student video\n'
          'UC-01 Save student video\nThe customer presses save. The system '
          'stores the video.',
      // page 4 — the second declared use-case table
      'Table 42. USE CASE - Rewind student video\n'
          'UC-02 Rewind student video\nThe customer presses rewind. The '
          'system rewinds.',
    ];
    final items = splitter.split(pages);

    final ids = items.map((i) => i.id).toSet();
    // UC units come from the TOC tables...
    expect(ids.contains('UC-01'), isTrue, reason: 'declared by the index');
    // ...and the prose FR survives; the statement "The system shall validate"
    // becomes a reviewable unit too.
    expect(ids.contains('FR-1'), isTrue, reason: 'prose FR must not be lost');
    expect(items.any((i) => i.id.startsWith('ST-')), isTrue);
    // Document order, not TOC-then-body order.
    final pageIndexes = items.map((i) => i.pageIndex!).toList();
    expect(pageIndexes, equals([...pageIndexes]..sort()));
  });

  // ------------------------------------------------------------ parser 1.4.0
  // Measured before the fix on a synthetic official-template SRS (Product
  // Overview → Actors → Use cases → Functional → Non-Functional → Appendix):
  // 12 units, six of them use-case stubs whose main flow had been cut off at
  // `1. User enters…`, and NONE of the twelve prose sections. The document
  // read as "use cases and nothing else". These cases pin the four causes.

  group('numbered steps do not cut a use case', () {
    test('period-terminated flow steps stay inside the open unit', () {
      final items = splitter.split([
        '''
2.2.2 Descriptions
UC-01 Login
Actor: Student
Main flow
1. User enters email and password.
2. User clicks Login.
3. System validates the credentials.
Alternative flow
1. If the password is wrong, the system shows an error.
Postconditions: User is redirected to the home page.
''',
      ]);

      expect(items.map((i) => i.id), ['UC-01']);
      expect(items.single.text, contains('System validates the credentials'));
      expect(items.single.text, contains('redirected to the home page'));
      expect(items.single.section, '2.2.2');
    });

    test('a Title Case step run without periods is still a flow', () {
      final items = splitter.split([
        '''
UC-01 Login
Main flow
1. Enter Email
2. Click Login
3. View Dashboard
UC-02 Logout
Main flow
1. Student clicks Logout
''',
      ]);

      expect(items.map((i) => i.id), ['UC-01', 'UC-02']);
      expect(items.first.text, contains('View Dashboard'));
      expect(items.last.text, contains('Student clicks Logout'));
    });

    test('Wiegers flow labels (1.0 / 1.1 / 1.0.E1) stay inside the unit', () {
      final items = splitter.split([
        '''
2.2.2 Descriptions
UC ID and Name: UC-01 Login
Primary Actor: Student
Normal Flow:
1.0 Login
1. User enters email and password.
2. System validates the credentials.
Alternative Flows:
1.1 Login with Google
1. User clicks Login with Google.
Exceptions:
1.0.E1 Invalid credentials
1. System shows message MSG-01.
Priority: High
3. Functional Requirements
3.1 Screen Flow
The screen flow diagram below shows how a student moves between the login,
catalog and course pages of the application.
''',
      ]);

      final uc = items.firstWhere((i) => i.id == 'UC-01');
      expect(uc.kind, RequirementKind.useCase);
      expect(uc.text, contains('Login with Google'));
      expect(uc.text, contains('Invalid credentials'));
      expect(uc.text, contains('Priority: High'));
      expect(uc.text, isNot(contains('Functional Requirements')));
      // The chapter heading that follows the last step is still a heading.
      final section = items.firstWhere((i) => i.id == 'SEC-3.1');
      expect(section.section, '3.1 Screen Flow');
    });

    test('a Vietnamese chapter right after step 2 is not step 3', () {
      final items = splitter.split([
        '''
2.2 Đặc tả use case
UC-01 Đăng nhập
Luồng chính
1. Sinh viên nhập email và mật khẩu
2. Hệ thống kiểm tra thông tin
3. Yêu cầu chức năng
3.1 Đăng nhập
Sinh viên nhập tài khoản và mật khẩu, hệ thống kiểm tra thông tin rồi
chuyển sang trang chủ của ứng dụng.
''',
      ]);

      final uc = items.firstWhere((i) => i.id == 'UC-01');
      expect(uc.text, contains('Hệ thống kiểm tra thông tin'));
      expect(uc.text, isNot(contains('Yêu cầu chức năng')));
      final section = items.firstWhere((i) => i.id == 'SEC-3.1');
      // Typed by the chapter above it: "Yêu cầu chức năng" → functional.
      expect(section.kind, RequirementKind.functional);
    });

    test('numbered table rows are content, not sections', () {
      final items = splitter.split([
        '''
2.1 Actors
# Actor Description
1 Guest A visitor who has not logged in.
2 Student A learner enrolled in courses.
3 Lecturer A staff member who creates courses and quizzes.
''',
      ]);

      expect(items.map((i) => i.id), ['SEC-2.1']);
      expect(items.single.text, contains('Guest'));
      expect(items.single.text, contains('Lecturer'));
    });
  });

  group('labelled use-case ids', () {
    test('Use Case ID / UC ID and Name / Use Case No. open the unit', () {
      final items = splitter.split([
        'Use Case ID: UC-01\nUse Case Name: Login\nActor: Student',
        'UC ID and Name: UC-02 Enroll course\nPrimary Actor: Student',
        'Use Case No. UC03\nUse case name: Reset password\nActor: Student',
      ]);

      expect(items.map((i) => i.id), ['UC-01', 'UC-02', 'UC-03']);
      expect(items.every((i) => i.kind == RequirementKind.useCase), isTrue);
      expect(items[1].text, startsWith('Enroll course'));
      expect(items[2].text, contains('Reset password'));
    });

    test('a bare "Use Case ID" label closes the previous table', () {
      final items = splitter.split([
        '''
Use Case ID
UC-01
Use Case Name
Login
Use Case ID
UC-02
Use Case Name
Logout
''',
      ]);

      expect(items.map((i) => i.id), ['UC-01', 'UC-02']);
      expect(items.first.text, isNot(contains('Use Case ID')));
    });

    test('a name row without an id still falls back to UC-T', () {
      final items = splitter.split(['Use case name: Submit weekly report']);
      expect(items.single.id, 'UC-T1');
    });
  });

  group('section fallback units', () {
    final pages = [
      '''
1. Product Overview
The Online Course Management System is a web application that helps
lecturers publish courses and lets students enroll, study and take quizzes.
It replaces the manual workflow and must integrate with Google Workspace.
2. User Requirements
2.1 Actors
# Actor Description
1 Guest A visitor who has not logged in.
2 Student A learner enrolled in one or more courses of the semester.
''',
      '''
3. Functional Requirements
3.2.1 Login Screen
Function trigger: User clicks the Login button.
Function description: The system validates the email and password, then
opens the home page for the role of the account.
4. Non-Functional Requirements
4.2.3 Performance
Every page loads within 3 seconds under normal load of 200 concurrent
users. Quiz submission completes within 1 second.
5. Requirement Appendix
5.1 Business Rules
BR-01 A user must have a university email to register.
BR-02 A student can enroll in at most 6 courses per semester.
5.2 Application Messages List
# Message Code Message Type Context
1 MSG-01 Invalid email or password. Error Login
2 MSG-05 The course is full. Warning Enroll
''',
    ];

    test('every prose section without an id becomes one unit', () {
      final items = splitter.split(pages);
      final byId = {for (final item in items) item.id: item};

      expect(
        byId.keys,
        containsAll([
          'SEC-1',
          'SEC-2.1',
          'SEC-3.2.1',
          'SEC-4.2.3',
          'BR-01',
          'BR-02',
          'SEC-5.2',
        ]),
      );
      // Kind follows the heading path, leaf first.
      expect(byId['SEC-1']!.kind, RequirementKind.section);
      expect(byId['SEC-2.1']!.kind, RequirementKind.section);
      expect(byId['SEC-3.2.1']!.kind, RequirementKind.functional);
      expect(byId['SEC-4.2.3']!.kind, RequirementKind.nonFunctional);
      expect(byId['SEC-5.2']!.kind, RequirementKind.section);
      expect(byId['BR-01']!.kind, RequirementKind.businessRule);
      // The section unit carries its heading for the prompt and the UI.
      expect(byId['SEC-4.2.3']!.section, '4.2.3 Performance');
      expect(byId['SEC-4.2.3']!.title, 'Performance');
      expect(byId['SEC-4.2.3']!.pageIndex, 1);
      expect(byId['SEC-4.2.3']!.text, contains('200 concurrent'));
    });

    test('a section that produced id units emits no section twin', () {
      final items = splitter.split(pages);
      expect(items.any((i) => i.id == 'SEC-5.1'), isFalse);
    });

    test('a "must" inside an overview paragraph stays with its prose', () {
      final items = splitter.split(pages);
      expect(items.any((i) => i.kind == RequirementKind.statement), isFalse);
      final overview = items.firstWhere((i) => i.id == 'SEC-1');
      expect(overview.text, contains('must integrate with Google Workspace'));
    });

    test('shall sentences under a requirements heading are typed by it', () {
      final items = splitter.split([
        '''
3.2 Functional Requirements
The system shall allow a lecturer to create a course.
The system shall send an email when enrollment succeeds.
''',
      ]);

      expect(items.map((i) => i.id), ['ST-1', 'ST-2']);
      expect(
        items.every((i) => i.kind == RequirementKind.functional),
        isTrue,
      );
    });

    test('too little prose is not a unit, and headings alone are nothing', () {
      final items = splitter.split([
        '1. Introduction\nSee chapter 3.\n2. Scope\n2.1 In scope\nEverything.',
      ]);
      expect(items, isEmpty);
    });

    test('numbering that restarts per part gets a distinct id', () {
      final items = splitter.split([
        '1.1 Purpose\nThis part describes the requirements of the system for '
            'lecturers and students in enough detail to build it.',
        '1.1 Design goals\nThe design follows a layered architecture with a '
            'thin client and a REST backend service behind a gateway.',
      ]);

      expect(items.map((i) => i.id), ['SEC-1.1', 'SEC-1.1-p2']);
    });

    test('a heading that carries an id opens that unit instead', () {
      final items = splitter.split([
        '''
2.2.2.1 UC-01 Login
Actor: Student
Main flow
1. Student enters email and password
2. System validates the credentials
3.1 System checks the password format
4. System shows the home page
2.2.2.2 UC-02 Logout
Actor: Student
''',
      ]);

      expect(items.map((i) => i.id), ['UC-01', 'UC-02']);
      expect(items.first.text, contains('checks the password format'));
      expect(items.first.text, contains('shows the home page'));
      expect(items.first.section, '2.2.2.1');
    });
  });

  group('kind by id prefix', () {
    test('NFR/NF are non-functional, BR is a business rule', () {
      final items = splitter.split([
        'NFR-01 The system shall respond within 2 seconds.',
        'NF-02 Hệ thống phải phản hồi trong 2s.',
        'BR-03 A student can enroll in at most 6 courses.',
        'FR-04 The system shall export a PDF.',
        'F-05: Trang chủ',
      ]);

      expect(items.map((i) => i.kind), [
        RequirementKind.nonFunctional,
        RequirementKind.nonFunctional,
        RequirementKind.businessRule,
        RequirementKind.functional,
        RequirementKind.functional,
      ]);
    });

    test('an id printed alone keeps the shall sentence that follows', () {
      final items = splitter.split([
        'FR-01\nThe system shall store each submitted report.\n'
            'The system shall notify the supervisor.',
      ]);

      expect(items.map((i) => i.id), ['FR-01', 'ST-1']);
      expect(items.first.text, contains('store each submitted report'));
      expect(items.last.text, contains('notify the supervisor'));
    });
  });
}
