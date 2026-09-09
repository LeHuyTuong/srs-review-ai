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
}
