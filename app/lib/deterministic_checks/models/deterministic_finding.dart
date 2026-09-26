/// Findings from the rule-based syllabus checks (F7/F8/F9).
///
/// These cost zero tokens and run offline, which is exactly why they are worth
/// having: they keep working when the network or the free-tier quota does not.
library;

import '../../requirement_review/models/report_language.dart'
    show ReportLanguage;
import '../../requirement_review/models/review_models.dart' show Severity;

enum CheckId {
  /// F7 — number of use cases in the SRS (syllabus: at least 20 medium UCs,
  /// no upper bound since rubric v3 / rulebook 1.5 Q1; size is F9's job).
  ucCount,

  /// F8 — documents must be written in English.
  language,

  /// F9 — each medium UC should hold 3–7 transactions.
  ucSize,

  /// M2 — same explicit id used by two or more requirements. Reuse is the
  /// signal, not the verdict: a real UC table may legitimately repeat UC04,
  /// so the finding names the id and the count, not a "fix it" command.
  duplicateIds,

  /// M2 — use case table does not declare a Postcondition / "điều kiện sau"
  /// section. This is the OTES SRS-01 finding in deterministic form: 63/63
  /// UCs without a measurable end-state, so a tester cannot know when the
  /// use case is "done".
  missingPostcondition,

  /// Round 11 — contradiction pass (goal §2 step 6, the "đắt nhất"
  /// family). Same entity (case-insensitive, plural-stripped) appears
  /// with two or more distinct original names across two or more
  /// sections of the document. The original 8 cross-artifact
  /// contradictions in the HisWise SDS review were all of this shape:
  /// one concept labelled differently in different diagrams.
  crossArtifactName,

  /// Round 13 — the use case text does not name an actor. A use case
  /// without an actor leaves the system boundary undefined: it is
  /// unclear whether the flow is driven by a human, another system,
  /// or time, and the test designer cannot pick a "who" to instrument.
  /// Structurally the same as [missingPostcondition] — a required
  /// sub-section is absent — so it lives in the same M2 family and
  /// renders under "Consistency smells" on the dashboard.
  missingActor,

  /// srs-writer skill, Ambiguity Detection auto-scan — a requirement
  /// sentence uses wording with no measurable threshold ("nhanh chóng",
  /// "user-friendly", "as needed"). IEEE 830 criterion 2 (Unambiguous) /
  /// 3 (Testable). Deliberately a conservative bilingual phrase list,
  /// not judgment — see quality_checks.dart for what was skipped and why.
  ambiguousWording,

  /// srs-writer skill, quality criterion 4 (Complete) — the document
  /// still carries "TBD" / "chưa xác định" / placeholder text that a
  /// submitted document must not have.
  placeholderTbd,

  /// sds-reviewer vision chains (steps 4-6): one row per audited page,
  /// family-numbered in page order (ERD-01, UC-02, …). The only
  /// model-evidence rows in the ledger — everything else is rule-based.
  diagramAudit,

  /// srs-writer skill, quality criterion 7 (Prioritized) — no
  /// requirement in the whole document names a priority. Priority lives
  /// in use-case table metadata, so this is a document-level verdict:
  /// firing means the field is absent everywhere, never a per-row flag.
  missingPriority,

  /// Rulebook 1.5 hard rule 6 — a non-functional requirement with no number
  /// AND no measurement condition. Distinct from [ambiguousWording], which
  /// fires on a fixed phrase list: this one fires on the *absence* of a
  /// figure, so "the system shall be available" trips it while
  /// "available 99.5% of the time, measured monthly" does not, even though
  /// neither contains a listed vague phrase. The rulebook grades this red;
  /// the app was silent on it until now.
  nfrUnquantified,

  // ------------------------------------------------ document index (blueprint)
  // These five read the document's own `List of Tables` / `List of Figures` /
  // chapter list (see `DocumentBlueprint`). They exist because the index is the
  // cheapest place to catch structural damage: a duplicated use-case caption or
  // a figure number that skips costs zero tokens to find, and no AI pass can
  // see it at all, because the AI only ever reads requirement text.

  /// Two or more tables in `List of Tables` share a caption. The classic
  /// copy-paste defect: three use cases in one real capstone LoT were all
  /// still called "Save student's video".
  duplicateCaption,

  /// A figure/table number is missing inside a section's run — the index jumps
  /// from 39 to 41. Not proof of a missing artifact (authors renumber), which
  /// is why it stays [Severity.low].
  numberingGap,

  /// A part a capstone report is expected to declare (Introduction, Project
  /// Management Plan, SRS, Design Description, Implementation & Test) is absent
  /// from the chapter list.
  missingSection,

  /// A figure caption names no recognisable diagram kind, so the vision pass
  /// cannot pick a judge for it from the index alone.
  unclassifiedFigure,

  /// The index points at a page where its caption is not: the page numbers are
  /// stale (usually because the file was edited but the index was not
  /// refreshed). Only reported when the blueprint's page mapping is trusted.
  captionPageMismatch,

  // ---------------------------------------------------- document furniture (§F)
  // These two read the page furniture — cover page and running header/footer
  // — instead of requirement text or the index. A furniture defect is
  // invisible to every other check: no requirement sentence carries it, the
  // index does not list it, and the AI pass only ever sees requirement text.

  /// Rulebook §F.1 (1.7-draft) — the cover page declares no label for one of
  /// the three fields a submitted capstone report must name: project title
  /// (high), supervisor (medium), group/members (low). Label heuristic over
  /// the first pages' text: a cover that prints the title big WITHOUT a
  /// label reads as missing — the documented false-positive direction — and
  /// a scanned cover (no text layer) stays silent instead (hard rule 3).
  coverPageInfo,

  /// Rulebook §F.2 (1.7-draft) — a line recurring at the same page edge
  /// across many pages exists in two variants that differ in a WORD, not
  /// just a number: the fingerprint of two document versions merged into
  /// one file (stale project name, last group's header). Pairs differing
  /// only in digits are numbering and never reported; chapter-varying
  /// running heads are the known false positive, which is why severity is
  /// pinned at low and the message says to verify visually.
  headerFooterConsistency,

  /// Rulebook §F.3 (1.7-draft) — the user's declaration (project title,
  /// supervisor) is not confirmed by what the cover page prints. Only this
  /// check can see the mismatch: it is the one place where a human vouched
  /// for a fact the file cannot state about itself. Silent when nothing was
  /// declared — the form is optional.
  projectInfoMismatch,

  /// Rulebook §F.4 (1.7-draft) — chapter ranges from the resolved index do
  /// not advance monotonically: a chapter starts before its predecessor
  /// ended. Reported only on a trusted index; "the index is a guess" must
  /// never become a finding.
  sectionOrder,

  /// §F.5a — a numbered heading exists without a parent level (3.1 with no
  /// 3) or the same number string is used twice. Reads parser-split
  /// `SEC-<n>` units only; unnumbered headings stay silent.
  headingNumbering,

  /// §F.5b — no page number at the end of any page (or a run that repeats
  /// / steps backwards), on text-extracted last lines. Heuristic by design:
  /// the text layer's "last line" is not the printed footer, so severity
  /// stays low and the message always asks for eyeballing.
  pageNumbering,

  /// §F.6 — the index claims a page whose caption is not near it, while the
  /// caption EXISTS elsewhere in the body: the artifact moved (typically
  /// dragged to the end, index not refreshed), which is a different defect
  /// from [captionPageMismatch] ("gone" — caption nowhere at all). Filled by
  /// the builder's whole-body sweep (`ArtifactRef.foundPageIndex`) only
  /// after the ±window search missed, reported only on a trusted index, and
  /// it silences [captionPageMismatch] for the same artifact: one artifact,
  /// one finding.
  tablePositionDrift;

  // NOT here, deliberately: `idFormat` (rulebook 1.5 §4, id shape).
  // `requirement_splitter._canonicalId` rewrites every parsed id to
  // `PREFIX-NN` before any check sees it, so a shape check would be grading
  // our own normalisation, not the document: every FR and NFR from a real
  // file would fail, and the malformed ids the rule targets (UC01, NFR01)
  // would already have been silently repaired. The check is worth having —
  // a malformed id drops its row out of every traceability join without an
  // error — but it needs the splitter to keep the raw source id alongside
  // the canonical one first. See review-rules/adapters/app-port-map.md §4.

  String get wire => switch (this) {
    CheckId.ucCount => 'uc_count',
    CheckId.language => 'language',
    CheckId.ucSize => 'uc_size',
    CheckId.duplicateIds => 'duplicate_ids',
    CheckId.missingPostcondition => 'missing_postcondition',
    CheckId.crossArtifactName => 'cross_artifact_name',
    CheckId.missingActor => 'missing_actor',
    CheckId.ambiguousWording => 'ambiguous_wording',
    CheckId.placeholderTbd => 'placeholder_tbd',
    CheckId.missingPriority => 'missing_priority',
    CheckId.diagramAudit => 'diagram_audit',
    CheckId.nfrUnquantified => 'nfr_unquantified',
    CheckId.duplicateCaption => 'duplicate_caption',
    CheckId.numberingGap => 'numbering_gap',
    CheckId.missingSection => 'missing_section',
    CheckId.unclassifiedFigure => 'unclassified_figure',
    CheckId.captionPageMismatch => 'caption_page_mismatch',
    CheckId.coverPageInfo => 'cover_page_info',
    CheckId.headerFooterConsistency => 'header_footer_consistency',
    CheckId.projectInfoMismatch => 'project_info_mismatch',
    CheckId.sectionOrder => 'section_order',
    CheckId.headingNumbering => 'heading_numbering',
    CheckId.pageNumbering => 'page_numbering',
    CheckId.tablePositionDrift => 'table_position_drift',
  };

  String get label => switch (this) {
    CheckId.ucCount => 'Use case count',
    CheckId.language => 'English only',
    CheckId.ucSize => 'Use case size',
    CheckId.duplicateIds => 'Duplicate requirement ids',
    CheckId.missingPostcondition => 'Missing postcondition',
    CheckId.crossArtifactName => 'Cross-artifact entity naming',
    CheckId.missingActor => 'Missing actor',
    CheckId.ambiguousWording => 'Vague wording',
    CheckId.placeholderTbd => 'TBD / placeholder',
    CheckId.missingPriority => 'Priority field',
    CheckId.diagramAudit => 'Diagram audit',
    CheckId.nfrUnquantified => 'Unquantified NFR',
    CheckId.duplicateCaption => 'Duplicate caption in index',
    CheckId.numberingGap => 'Index numbering gap',
    CheckId.missingSection => 'Missing report part',
    CheckId.unclassifiedFigure => 'Unclassified figure',
    CheckId.captionPageMismatch => 'Index page out of date',
    CheckId.coverPageInfo => 'Cover page info',
    CheckId.headerFooterConsistency => 'Header/footer consistency',
    CheckId.projectInfoMismatch => 'Declared info vs cover',
    CheckId.sectionOrder => 'Chapter order',
    CheckId.headingNumbering => 'Heading numbering',
    CheckId.pageNumbering => 'Page numbering',
    CheckId.tablePositionDrift => 'Artifact moved from index page',
  };

  /// True for the §F.5 format & layout checks. They are STORED in
  /// `referenceFindings` like the rest of the §F furniture — persistence,
  /// export and the Verifier already travel that list, no new state field
  /// needed — but the dashboard gives them their own "Format & Layout"
  /// section: a heading-hierarchy defect is a presentation problem, not a
  /// consistency smell.
  bool get isFormatCheck =>
      this == CheckId.headingNumbering || this == CheckId.pageNumbering;

  /// True for the document-index (blueprint) checks. They read the table of
  /// contents rather than the requirement text, so the dashboard groups them
  /// separately from both F7/F8/F9 and the M2 reference checks — their fixes
  /// live in the index/artifacts, not in a requirement sentence.
  bool get isBlueprintCheck => switch (this) {
    CheckId.duplicateCaption ||
    CheckId.numberingGap ||
    CheckId.missingSection ||
    CheckId.unclassifiedFigure ||
    CheckId.captionPageMismatch ||
    CheckId.sectionOrder ||
    CheckId.tablePositionDrift => true,
    _ => false,
  };

  /// True for M2 reference checks; they live next to F7/F8/F9 in the
  /// deterministic family but are reported under their own section so the
  /// dashboard can keep "syllabus failures" and "consistency smells"
  /// visually separate. The §F document-furniture checks ride the same
  /// `referenceFindings` list and dashboard section (the ContradictionPass
  /// round-12 fold): a stale header or a bare cover is a document-wide
  /// consistency smell, not a syllabus threshold.
  bool get isReferenceCheck => switch (this) {
    CheckId.duplicateIds ||
    CheckId.missingPostcondition ||
    CheckId.crossArtifactName ||
    CheckId.missingActor ||
    CheckId.coverPageInfo ||
    CheckId.headerFooterConsistency ||
    CheckId.projectInfoMismatch ||
    CheckId.headingNumbering ||
    CheckId.pageNumbering => true,
    _ => false,
  };
}

/// True if [key] looks like a deterministic finding key
/// (`<wire>:<subject>`), false otherwise.
///
/// Used by callers that share a status map between AI finding ids
/// (which look like `SEQ-CLS-01`) and deterministic finding keys
/// (which always start with a known [CheckId.wire] value). The
/// Verifier only ever transitions the deterministic subset — AI
/// findings carry a verdict the deterministic path cannot re-derive.
bool isDeterministicFindingKey(String key) {
  for (final check in CheckId.values) {
    if (key.startsWith('${check.wire}:')) return true;
  }
  return false;
}

class DeterministicFinding {
  /// One finding, with its message in BOTH report languages.
  ///
  /// Both are required, and that is the point (2026-09-25). The report used to
  /// be half English and half Vietnamese because each check wrote its message
  /// in whichever language its author used that day, so an exported file made a
  /// supervisor switch language mid-page. "Both required" makes the compiler
  /// the enforcement: a new check cannot be added without deciding what it says
  /// in each language, and no call site can pick a language by accident
  /// because there is no single-language field left to read.
  ///
  /// The subtlety in each pair is the SAME interpolated data in both strings —
  /// the same id, the same count, the same missing numbers. A translation that
  /// quietly restates different facts is the failure this shape invites, which
  /// is why the twins sit next to each other in the check that raises them.
  const DeterministicFinding({
    required this.check,
    required this.passed,
    required this.severity,
    required this.messageEn,
    required this.messageVi,
    this.subject,
    this.actual,
    this.expectedMin,
    this.expectedMax,
    this.requiresVisionEvidence = false,
  });

  /// Both languages the same string.
  ///
  /// For a message that carries no prose (an id, a count, a slug) and for the
  /// synthetic findings the test suite builds — those assert arithmetic, not
  /// wording, and duplicating a fixture string twice would be noise.
  const DeterministicFinding.both({
    required this.check,
    required this.passed,
    required this.severity,
    required String message,
    this.subject,
    this.actual,
    this.expectedMin,
    this.expectedMax,
    this.requiresVisionEvidence = false,
  }) : messageEn = message,
       messageVi = message;

  factory DeterministicFinding.fromJson(Map<String, dynamic> json) {
    // `message` is the pre-2026-09-25 single-language field (and the field a
    // saved session still carries): it holds the Vietnamese twin, so a session
    // written before this change opens as a Vietnamese report, and an English
    // report falls back to it only when `message_en` is absent.
    final legacy = json['message'] as String? ?? '';
    return DeterministicFinding(
      check: CheckId.values.firstWhere((value) => value.wire == json['check']),
      passed: json['passed'] as bool,
      severity: Severity.values.firstWhere(
        (value) => value.name == json['severity'],
      ),
      messageEn: json['message_en'] as String? ?? legacy,
      messageVi: json['message_vi'] as String? ?? legacy,
      subject: json['subject'] as String?,
      actual: json['actual'] as num?,
      expectedMin: json['expected_min'] as num?,
      expectedMax: json['expected_max'] as num?,
      requiresVisionEvidence:
          json['requires_vision_evidence'] as bool? ?? false,
    );
  }

  final CheckId check;

  /// The finding's stable identity in the re-review ledger — the exact
  /// key the Verifier stores statuses under and the key the report
  /// twins look up to render OPEN/FIXED/VERIFIED per row. Lives here
  /// (not only inside Verifier._keyOf) so exporter and verifier can
  /// never drift apart on formatting.
  String get ledgerKey => '${check.wire}:${subject ?? '_'}';
  final bool passed;
  final Severity severity;

  /// The finding's message in English. Read it through [messageFor], never
  /// directly: a builder that reads one side of the pair is how a report
  /// becomes half one language and half the other again.
  final String messageEn;

  /// The finding's message in Vietnamese.
  final String messageVi;

  /// The message in the report language the user chose.
  String messageFor(ReportLanguage language) =>
      language == ReportLanguage.vietnamese ? messageVi : messageEn;

  /// The UC/requirement id this is about; null for document-level findings.
  final String? subject;
  final num? actual;
  final num? expectedMin;
  final num? expectedMax;

  /// True when this finding cannot be verified by deterministic
  /// re-derivation alone — it needs vision (LLM call on the actual
  /// diagram) or some other out-of-Dart evidence. The Verifier honors
  /// this by seeding the row with `FindingStatus.pendingVision` instead
  /// of `open`, per goal §3 rule 3 ("MỤC TIÊU KHÔNG KIỂM ĐƯỢC → dòng
  /// ⬜ PENDING-VISION, tuyệt đối không được tô xanh").
  final bool requiresVisionEvidence;

  Map<String, dynamic> toJson() => {
    'check': check.wire,
    'passed': passed,
    'severity': severity.name,
    // Both sides are persisted: a session saved after this change reopens in
    // whichever language the user picks, and `message` keeps the older readers
    // (and the pre-change sessions) working.
    'message': messageVi,
    'message_en': messageEn,
    'message_vi': messageVi,
    'subject': subject,
    'actual': actual,
    'expected_min': expectedMin,
    'expected_max': expectedMax,
    'requires_vision_evidence': requiresVisionEvidence,
  };
}
