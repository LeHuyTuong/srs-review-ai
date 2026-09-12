/// Synthetic OTES demo inventory — a faithful Dart port of the brief's
/// `src/lib/demo.ts`.
///
/// Deliberately synthetic (the brief is explicit about this): content is
/// inspired by an Online Testing & Examination System SRS but is NOT a
/// reproduction of any student's document. It exists so the full flow can be
/// demonstrated offline — no file picker, no network, no quota.
library;

import '../../../data/models/srs_document.dart';

const String demoFileName = 'OTES_SRS_v1.0.pdf';
const int demoPageCount = 114;

const List<String> _useCaseNames = [
  'Register account',
  'Log in',
  'Log out',
  'Reset password',
  'View user profile',
  'Update user profile',
  'Change password',
  'Manage user accounts',
  'Create an examination',
  'Update an examination',
  'View examination details',
  'Delete an examination',
  'Publish an examination',
  'Search examinations',
  'Register for an examination',
  'Cancel examination registration',
  'View examination schedule',
  'Manage question bank',
  'Create a question',
  'Update a question',
  'Delete a question',
  'Import questions',
  'Export questions',
  'Generate examination paper',
  'Review examination paper',
  'Assign an invigilator',
  'Start an examination',
  'Submit examination answers',
  'Save examination progress',
  'View remaining time',
  'Auto-submit examination',
  'Grade an examination',
  'Review examination results',
  'Publish examination results',
  'View student results',
  'Request a regrade',
  'Approve a regrade',
  'Generate results report',
  'Export results',
  'Send a notification',
  'View notifications',
  'Manage departments',
  'Manage subjects',
  'Manage classes',
  'Enroll a student',
  'View activity logs',
  'Configure examination rules',
  'Manage access permissions',
  'Archive an examination',
  'View dashboard',
];

const List<String> _businessRuleNames = [
  'Unique email address',
  'Password policy',
  'Examination eligibility',
  'Attempt limit',
  'Submission deadline',
  'Grading policy',
  'Role-based access',
  'Data retention',
];

const List<String> _nonFunctionalNames = [
  'System performance',
  'Availability',
  'Security',
  'Usability',
  'Compatibility',
];

String _useCaseText(String id, String title, int i) =>
    '$id $title\n'
    'Actor: Student\n'
    'Preconditions\n'
    'The student has access to the Online Testing & Examination System.\n'
    'Main flow\n'
    '1. The student selects ${title.toLowerCase()}.\n'
    '2. The system displays the required form.\n'
    '3. The student enters the required information.\n'
    '4. The system validates the information and '
    '${i % 7 == 0 ? 'quickly completes the request' : 'displays a confirmation'}.\n'
    'Postconditions\n'
    'The request is recorded in the system.'
    '${i % 9 == 0 ? '' : '\nAlternative flow\n1. If validation fails, the '
              'system displays an error and preserves the input.'}\n'
    'Business rules\nOnly authorized users may perform this action.';

/// The parsed requirements behind "Load the sample document".
///
/// 50 use cases + 8 business rules + 5 non-functional requirements, plus the
/// two malformed ids the brief keeps visible as unclassified units
/// (`UC0134`, `UC0114`).
SrsDocument demoDocument() {
  final items = <RequirementItem>[];
  var page = 11;
  for (var i = 0; i < _useCaseNames.length; i++) {
    final id = 'UC${(i + 1).toString().padLeft(2, '0')}';
    final title = _useCaseNames[i];
    items.add(
      RequirementItem(
        id: id,
        text: _useCaseText(id, title, i),
        kind: RequirementKind.useCase,
        section: '3.1 User management',
        pageIndex: page,
      ),
    );
    page += 1 + (i % 2);
  }
  for (var i = 0; i < _businessRuleNames.length; i++) {
    final id = 'BR${(i + 1).toString().padLeft(2, '0')}';
    final title = _businessRuleNames[i];
    items.add(
      RequirementItem(
        id: id,
        text:
            '$id $title\nThe system must enforce ${title.toLowerCase()} for '
            'every relevant transaction.',
        kind: RequirementKind.functional,
        section: '3.2 Business rules',
        pageIndex: 99 + i,
      ),
    );
  }
  const nfrText = [
    'The system should respond quickly to user requests.',
    'The system must meet the documented acceptance criteria.',
    'The system must meet the documented acceptance criteria.',
    'The interface must be user-friendly and easy to use.',
    'The system must meet the documented acceptance criteria.',
  ];
  for (var i = 0; i < _nonFunctionalNames.length; i++) {
    final id = 'NFR${(i + 1).toString().padLeft(2, '0')}';
    items.add(
      RequirementItem(
        id: id,
        text: '$id ${_nonFunctionalNames[i]}\n${nfrText[i]}',
        kind: RequirementKind.functional,
        section: '4. Non-functional requirements',
        pageIndex: 108 + i,
      ),
    );
  }
  const malformed = ['UC0134', 'UC0114'];
  const malformedTitles = [
    'Update examination status',
    'View examination history',
  ];
  for (var i = 0; i < malformed.length; i++) {
    items.add(
      RequirementItem(
        id: malformed[i],
        text:
            '${malformed[i]} ${malformedTitles[i]}\nMain flow\n1. Student '
            'opens the examination.\n2. System displays the examination details.',
        kind: RequirementKind.functional,
        section: null,
        pageIndex: 78 + i * 4,
      ),
    );
  }

  final pageTexts = List<String>.generate(
    demoPageCount,
    (p) => items
        .where((item) => item.pageIndex == p)
        .map((item) => item.text)
        .join('\n\n'),
  );

  return SrsDocument(
    fileName: demoFileName,
    pageCount: demoPageCount,
    pageTexts: pageTexts,
    requirements: items,
    imagePageIndexes: const [],
  );
}
