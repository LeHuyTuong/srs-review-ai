/// Report language — the one switch that decides which language an exported
/// report is written in (2026-09-25).
///
/// Lives in the DATA layer, not next to the report builders: `data/` may not
/// import from `features/` (guardrail `data-no-features`), and
/// `DeterministicFinding` — a data model every report row comes from — has to
/// speak this enum to expose its message in both languages. Features import
/// down into here; the reverse would be a layering violation, which is exactly
/// how `verifier.dart` once ended up importing upward.
///
/// Why the switch exists: the report used to be a mix. The scaffolding was
/// English, but the deterministic checks had authored their messages in
/// whichever language their author wrote that day — `syllabus_checks.dart` in
/// English, `project_info_checks.dart` in Vietnamese, `blueprint_checks.dart`
/// in Vietnamese — so a single exported file carried both, and a supervisor
/// reading it had to switch languages mid-page. The rule now is: **one report,
/// one language, whichever the user picked.**
///
/// Two things the app cannot translate, and the report says so instead of
/// pretending: a `quote` is evidence the server verified verbatim against the
/// document (translating it would break the one guarantee that separates a
/// finding from an assertion), and an AI `suggestion` is model output produced
/// under the prompt's own language rule. A request-level output language is the
/// honest fix for the second, and it is a separate change.
library;

/// The language an exported report is written in.
///
/// `vietnamese` is first because it is the app-wide default: the UI is
/// Vietnamese and the document under review is a Vietnamese capstone report.
enum ReportLanguage {
  vietnamese('vi', 'Tiếng Việt'),
  english('en', 'English');

  const ReportLanguage(this.wire, this.label);

  /// Stable token for anything that persists the choice.
  final String wire;

  /// What the language switch shows the user.
  final String label;

  /// Unknown / absent reads as Vietnamese — the app default, and the safe
  /// direction: guessing English would silently hand an English report to
  /// someone who asked for Vietnamese.
  static ReportLanguage fromWire(String? value) =>
      value == english.wire ? english : vietnamese;
}
