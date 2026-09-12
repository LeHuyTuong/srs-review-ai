import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_detector.dart';

/// [DiagramDetector] decisions, not string mechanics.
///
/// The detector gates whether a later milestone attaches a page image to the
/// review request. A miss means the requirement is reviewed without its
/// diagram context and the finding is wrong-but-confident — so the tests
/// lean on recall: every phrasing a student actually writes must fire.
void main() {
  const detector = DiagramDetector();

  group('detects diagram intent in', () {
    for (final entry in {
      'plain english': 'The system shall render the class diagram.',
      'plural': 'All diagrams must use the project template.',
      'figure reference': 'See Figure 3 for the checkout flow.',
      'erd acronym': 'The ERD covers student and course entities.',
      'uml': 'UML notation is required for all models.',
      'compound use case': 'The use case diagram matches Report 3.',
      'vietnamese lowcase': 'sơ đồ tuần tự đặt trên trang 12.',
      'vietnamese hình': 'Hình 4 minh họa luồng đăng nhập.',
      'lược đồ': 'Lược đồ cơ sở dữ liệu gồm 5 bảng.',
      'biểu đồ': 'Biểu đồ activity thể hiện nghiệp vụ mượn sách.',
    }.entries) {
      test(entry.key, () {
        final signal = detector.detect(entry.value);
        expect(signal.mentionsDiagram, isTrue, reason: entry.value);
        expect(signal.matchedTerm, isNotNull, reason: entry.value);
      });
    }
  });

  test('stays silent on ordinary functional text', () {
    for (final text in [
      'The system shall send a confirmation email within 60 seconds.',
      'Passwords are stored hashed with bcrypt.',
      'The form blocks submission when the student id is missing.',
    ]) {
      final signal = detector.detect(text);
      expect(signal.mentionsDiagram, isFalse, reason: text);
      expect(signal.matchedTerm, isNull, reason: text);
    }
  });

  test(
    'false positives are acceptable, false negatives are not — case fold',
    () {
      expect(detector.detect('CLASS DIAGRAM').mentionsDiagram, isTrue);
      expect(detector.detect('Sơ Đồ').mentionsDiagram, isTrue);
    },
  );

  test('first keyword wins and is reported for audit', () {
    final signal = detector.detect('The diagram and the wireframe agree.');
    expect(signal.matchedTerm, 'diagram');
  });

  test('empty and blank text produce a silent signal', () {
    expect(detector.detect('').mentionsDiagram, isFalse);
    expect(detector.detect('   \n\t ').mentionsDiagram, isFalse);
  });

  test('signal is a value object', () {
    expect(
      const DiagramSignal(mentionsDiagram: true, matchedTerm: 'diagram'),
      const DiagramSignal(mentionsDiagram: true, matchedTerm: 'diagram'),
    );
    expect(
      const DiagramSignal(mentionsDiagram: true, matchedTerm: 'diagram'),
      isNot(const DiagramSignal(mentionsDiagram: false)),
    );
  });
}
