/// Document-index checks (0 token) — the ones that read the `List of Tables` /
/// `List of Figures` / chapter list instead of requirement prose.
///
/// Why they earn their place next to F7/F8/F9: the AI pass only ever sees
/// requirement text, so a structural defect that lives in the index is
/// invisible to it by construction. Two tables announcing the same use case,
/// a figure number that skips 40, a missing SRS chapter — all of it is
/// detectable in milliseconds, offline, before a single token is spent. On a
/// real capstone LoT this family found three duplicated use-case captions and
/// a broken figure run.
///
/// Contract: only failures are emitted (a blueprint check that passes produces
/// no finding), matching `QualityChecks`. Callers treat "no finding" as pass and
/// never have to filter a passing row out of the ledger.
library;

import '../models/deterministic_finding.dart';
import '../models/document_blueprint.dart';
import '../models/review_models.dart' show Severity;
import 'diagram_type_classifier.dart' show DiagramKind;

/// A report part a frame expects, matched against the chapter TITLE — never a
/// page number or a letter. Reports divide themselves by page and letter their
/// parts differently; the only thing a check may pin down is the title.
class ExpectedSection {
  const ExpectedSection(this.name, this.patternSource, this.severity);

  /// The part's name, used as the finding subject ("Software Requirement
  /// Specification").
  final String name;

  /// Kept as source and compiled on demand, so instances can be `const` and
  /// the default frame can be a const list (RegExp has no const constructor).
  final String patternSource;
  final Severity severity;

  RegExp get pattern => RegExp(patternSource, caseSensitive: false);
}

class BlueprintChecks {
  /// [expectedSections] is the frame a report is judged against, and
  /// deliberately a parameter: the default mirrors one capstone outline, but a
  /// report built on a different structure must not be told it is "missing"
  /// parts it was never asked to write. [BlueprintChecks.missingSections]
  /// additionally self-disables when the document speaks no part of the frame.
  ///
  /// [maxGap] is the largest jump inside one section's run that still counts
  /// as a missing number rather than a new run (see [BlueprintChecks.numberingGaps]).
  const BlueprintChecks({
    this.expectedSections = defaultExpectedSections,
    this.maxGap = 3,
  });

  /// The frame this instance judges against.
  final List<ExpectedSection> expectedSections;

  /// A gap wider than this counts as "the index started a new run" rather than
  /// a missing artifact. Verified against a real capstone LoT/LoF: the genuine
  /// gaps are 1–2 apart (39 -> 41), while the wide jumps (Table 23 -> Table 40)
  /// are chapters whose tables simply start again.
  final int maxGap;

  /// The default frame — the five parts one capstone outline declares. Titles
  /// only: one document calls part B "Project Management Plan", the next
  /// "Software Project Management Plan", and a third renumbers everything.
  static const List<ExpectedSection> defaultExpectedSections = [
    ExpectedSection('Introduction', r'introduction', Severity.medium),
    ExpectedSection(
      'Project Management Plan',
      r'project management|management plan',
      Severity.medium,
    ),
    ExpectedSection(
      'Software Requirement Specification',
      r'software requirement specification|requirement specification|\bsrs\b',
      Severity.high,
    ),
    ExpectedSection(
      'Software Design Description',
      r'design description|\bsdd\b|system design',
      Severity.medium,
    ),
    ExpectedSection(
      'System Implementation & Test',
      r'implementation|system test|test plan|testing',
      Severity.medium,
    ),
  ];

  /// How many parts of a frame must match before the frame applies. A single
  /// "Introduction" is a word almost every document has; two matching parts
  /// means the document really was built on this frame.
  static const int minFrameMatches = 2;

  List<DeterministicFinding> runAll(DocumentBlueprint? blueprint) {
    if (blueprint == null || blueprint.isEmpty) return const [];
    return [
      ...duplicateCaptions(blueprint),
      ...numberingGaps(blueprint),
      ...missingSections(blueprint),
      ...unclassifiedFigures(blueprint),
      ...captionPageMismatches(blueprint),
    ];
  }

  // ------------------------------------------------------ duplicate captions

  /// Two tables the index names identically. Grouped by
  /// [ArtifactRef.normalizedCaption] so `USE CASE – Kick a student out of
  /// group` and `Use Case - Kick a Student out of Group` are one defect.
  ///
  /// [Severity.medium]: a duplicated caption means two use cases are
  /// indistinguishable in every traceability view the team builds later.
  List<DeterministicFinding> duplicateCaptions(DocumentBlueprint blueprint) {
    final byCaption = <String, List<ArtifactRef>>{};
    for (final artifact in blueprint.tables) {
      if (artifact.normalizedCaption.isEmpty) continue;
      byCaption.putIfAbsent(artifact.normalizedCaption, () => []).add(artifact);
    }

    final findings = <DeterministicFinding>[];
    for (final entry in byCaption.entries) {
      final group = entry.value;
      if (group.length < 2) continue;
      final listing = group
          .map((a) => '${a.label} (trang ${a.printedPage})')
          .join(', ');
      findings.add(
        DeterministicFinding(
          check: CheckId.duplicateCaption,
          passed: false,
          severity: Severity.medium,
          message:
              '${group.length} bảng dùng cùng tên "${group.first.caption}": '
              '$listing. Mỗi use case phải có tên riêng, nếu không thì không '
              'phân biệt được trong mọi bảng truy vết.',
          subject: group.first.normalizedCaption,
          actual: group.length,
        ),
      );
    }
    return findings;
  }

  // --------------------------------------------------------- numbering gaps

  /// A missing number inside a run — `Figure 39` then `Figure 41`.
  ///
  /// Only reported when the two neighbours sit in the same section and the gap
  /// is [maxGap] or less. Without both conditions the check is noise: a real
  /// 94-figure LoF produced eight "gaps", seven of which were simply the next
  /// chapter starting its own numbering.
  ///
  /// [Severity.low]: authors renumber, and the index is not the artifact.
  List<DeterministicFinding> numberingGaps(DocumentBlueprint blueprint) {
    final findings = <DeterministicFinding>[];
    for (final kind in ArtifactKind.values) {
      final artifacts = blueprint.artifacts
          .where((a) => a.kind == kind)
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      for (var i = 1; i < artifacts.length; i++) {
        final previous = artifacts[i - 1];
        final current = artifacts[i];
        if (current.number == previous.number) continue; // duplicates are C1
        final gap = current.number - previous.number - 1;
        if (gap < 1 || gap > maxGap) continue;
        if (previous.sectionId == null ||
            previous.sectionId != current.sectionId) {
          continue;
        }
        final missing = [
          for (var n = previous.number + 1; n < current.number; n++)
            kind == ArtifactKind.figure ? 'Figure $n' : 'Table $n',
        ];
        findings.add(
          DeterministicFinding(
            check: CheckId.numberingGap,
            passed: false,
            severity: Severity.low,
            message:
                '${current.label} nhảy từ ${previous.label} '
                '(thiếu ${missing.join(', ')}). Kiểm tra xem bảng/hình đó có bị '
                'xoá mà quên cập nhật mục lục không.',
            subject: '${kind == ArtifactKind.figure ? 'figure' : 'table'}'
                ':${previous.number}-${current.number}',
            actual: gap,
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------- missing sections

  /// Report parts the chapter list never declares. [Severity.high] for the SRS
  /// part — no requirements chapter means there is nothing else to grade.
  ///
  /// The check judges a frame, not a document class: it only runs when the
  /// document demonstrably speaks the frame (at least [minFrameMatches]
  /// expected parts found). A report built on its own structure would fail
  /// every pattern at once, and flagging all of them would teach users to
  /// ignore the check — the failure direction that kills a checker.
  List<DeterministicFinding> missingSections(DocumentBlueprint blueprint) {
    if (blueprint.sections.isEmpty) return const [];
    final declared = <ExpectedSection>{};
    for (final expected in expectedSections) {
      final found = blueprint.sections.any(
        (section) => section.matchesTitle(expected.pattern),
      );
      if (found) declared.add(expected);
    }
    // The frame applies when enough of it shows up. `minFrameMatches` for a
    // full-size frame (one "Introduction" alone proves nothing); half the parts
    // for a small one (a 2-part frame can only ever be half missing, and that
    // half is exactly what the check must catch).
    final halfFrame = (expectedSections.length + 1) ~/ 2;
    final threshold = minFrameMatches < halfFrame ? minFrameMatches : halfFrame;
    if (declared.length < threshold) return const [];

    final findings = <DeterministicFinding>[];
    for (final expected in expectedSections) {
      if (declared.contains(expected)) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.missingSection,
          passed: false,
          severity: expected.severity,
          message:
              'Mục lục không có phần "${expected.name}". Báo cáo đồ án phải '
              'khai báo đủ các phần này.',
          subject: expected.name,
        ),
      );
    }
    return findings;
  }

  // ---------------------------------------------------- unclassified figures

  /// Figures whose caption names no diagram kind, so the vision pass cannot
  /// pick a judge for them from the index alone.
  List<DeterministicFinding> unclassifiedFigures(DocumentBlueprint blueprint) {
    final findings = <DeterministicFinding>[];
    for (final figure in blueprint.figures) {
      if (figure.diagramKind != DiagramKind.unknown) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.unclassifiedFigure,
          passed: false,
          severity: Severity.low,
          message:
              '${figure.label} ("${figure.caption}") không nói rõ đây là loại '
              'sơ đồ gì. Đặt caption theo loại sơ đồ (class diagram, sequence '
              'diagram, ERD…) để hệ thống chấm đúng bộ tiêu chí.',
          subject: figure.label,
        ),
      );
    }
    return findings;
  }

  // -------------------------------------------------- stale index page numbers

  /// Entries the builder could not find where the index said they would be.
  ///
  /// Gated on [DocumentBlueprint.trusted]: when the offset itself could not be
  /// verified, an unresolved artifact says nothing about the document — it says
  /// the index has no page numbers to verify against.
  List<DeterministicFinding> captionPageMismatches(
    DocumentBlueprint blueprint,
  ) {
    if (!blueprint.trusted) return const [];
    final findings = <DeterministicFinding>[];
    for (final artifact in blueprint.artifacts) {
      if (artifact.isResolved) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.captionPageMismatch,
          passed: false,
          severity: Severity.low,
          message:
              'Mục lục ghi ${artifact.label} ở trang ${artifact.printedPage} '
              'nhưng không tìm thấy caption quanh trang đó. Có thể mục lục chưa '
              'được cập nhật lại sau khi sửa nội dung (bấm Update Field trong '
              'Word).',
          subject: artifact.label,
          actual: artifact.printedPage,
        ),
      );
    }
    return findings;
  }
}