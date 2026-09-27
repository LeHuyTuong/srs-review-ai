/// Round 11 — contradiction pass (goal §2 step 6, the "đắt nhất" family).
///
/// In the HisWise SDS review the eight most expensive findings were all
/// the same shape: one entity labelled differently in two diagrams. The
/// deterministic path cannot see diagrams, so this pass operates on the
/// *text* of the requirement titles and reproduces a weaker version of
/// the same signal — same entity stem, two distinct original strings,
/// two distinct sections — which still catches the spelling / casing /
/// plural variation pattern the LLM pass would catch at much higher
/// cost.
///
/// It is a pure function over [SrsDocument] (no I/O, no LLM), runs at
/// import time alongside the rest of the deterministic family, and emits
/// a [DeterministicFinding] for every cluster that crosses both
/// thresholds. The dashboard already renders this family under its own
/// "Consistency smells" heading (R6), so an emitted finding appears
/// without further UI work.
///
/// What it deliberately does NOT do:
///
///   - Syntactic / semantic matching: two strings are "the same entity"
///     iff their normalised stems match character-by-character. There
///     is no embedding, no LLM, no edit-distance fuzzy match. The
///     tradeoff is fewer false positives (Customer ≠ Client) and more
///     false negatives (Customer Login ≠ Customer Session).
///   - Cross-language matching: the strip is ASCII only. An SRS in
///     Vietnamese that mentions "Khách hàng" and "khách hàng" twice in
///     the same section will not collapse — those are still two distinct
///     originals to this pass.
library;

import '../../diagram_audit/services/cross_artifact_checker.dart';
import '../../document_import/models/srs_document.dart';
import '../../requirement_review/models/review_models.dart';
import '../models/deterministic_finding.dart';

class ContradictionPass {
  const ContradictionPass();

  /// Returns one [DeterministicFinding] per entity stem that appears
  /// under ≥ 2 distinct original strings across ≥ 2 distinct sections.
  ///
  /// Pass / fail semantics: the check is [DeterministicFinding.passed]
  /// false when any contradiction is found, true otherwise. A document
  /// with zero detected contradictions still yields an empty list —
  /// the dashboard renders nothing for the family.
  List<DeterministicFinding> detect(SrsDocument doc) {
    // (stem → (originals seen, sections seen))
    final clusters = <String, _Cluster>{};

    for (final req in doc.requirements) {
      final original = _extractEntityName(req.text);
      if (original == null) continue;
      final stem = _stem(original);
      final section = req.section ?? '(no section)';
      final cluster = clusters.putIfAbsent(
        stem,
        () => _Cluster(originals: <String>{}, sections: <String>{}),
      );
      cluster.originals.add(original);
      cluster.sections.add(section);
    }

    final findings = <DeterministicFinding>[];
    for (final entry in clusters.entries) {
      final stem = entry.key;
      final cluster = entry.value;
      // Need both: two distinct originals (so the name really varies)
      // AND two distinct sections (so the variation is across parts
      // of the document, not just two consecutive rows in one table).
      if (cluster.originals.length < 2 || cluster.sections.length < 2) {
        continue;
      }
      final variantList = cluster.originals.toList()..sort();
      final sectionList = cluster.sections.toList()..sort();
      findings.add(
        DeterministicFinding(
          check: CheckId.crossArtifactName,
          passed: false,
          severity: Severity.high,
          messageEn:
              'Entity "$stem" appears as ${variantList.join(", ")} '
              'across ${sectionList.length} sections '
              '(${sectionList.join(", ")}). Same concept, '
              'different labels — pick one name.',
          messageVi:
              'Thực thể "$stem" xuất hiện dưới các tên '
              '${variantList.join(", ")} trong ${sectionList.length} mục '
              '(${sectionList.join(", ")}). Cùng một khái niệm nhưng khác '
              'nhãn — hãy chọn một tên.',
          subject: stem,
          actual: variantList.length,
          // Vision-required: text-level name variation is a *signal*
          // but verifying the variants really refer to one entity
          // needs the class diagram (out of the text-only pipeline's
          // reach). Per goal §3 rule 3 these start as pendingVision
          // and only graduate to verified when vision or explicit
          // user confirmation resolves them.
          requiresVisionEvidence: true,
        ),
      );
    }
    return findings;
  }

  // ----------------------------------------------------------------- helpers

  /// Returns the first capitalised multi-word phrase in [title], or
  /// null when nothing capitalised exists. The detector is intentionally
  /// shallow — it does not parse, does not lemmatise, does not
  /// disambiguate.
  ///
  /// Bilingual since 2026-09-26 (plan 9 P1). The old pattern was ASCII-only,
  /// so on the Vietnamese OTES it matched nothing and chain 1 reported a
  /// **false 0** — measured in
  /// docs/evidence/r13_otes_deterministic_ceiling.md:29, where the honest
  /// reading was "this check found nothing", not "this document is clean".
  /// A silent zero is worse than a false positive, so Vietnamese capitals
  /// (Sinh viên, Khách hàng, Tác nhân) are matched now, following the
  /// precedent `missingActor` already set with its EN+VN phrase list.
  static String? _extractEntityName(String title) {
    final match = RegExp(
      r'[A-ZÀ-Ỹ][a-zà-ỹ]+(?:\s+[A-ZÀ-Ỹ][a-zà-ỹ]+)*',
    ).firstMatch(title);
    return match?.group(0);
  }

  /// Delegates to the ONE normaliser every cross-artifact comparison uses
  /// (`CrossArtifactChecker.stemOf`). A second copy here is how the diagram
  /// side and the text side drift into disagreeing about what "the same
  /// name" means — a false negative on every genuine match, and nothing in
  /// review would catch it.
  static String _stem(String name) => stemOf(name);
}

class _Cluster {
  _Cluster({required this.originals, required this.sections});
  final Set<String> originals;
  final Set<String> sections;
}
