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
  /// disambiguate. "Customer Profile" returns "Customer Profile";
  /// "the quick brown fox" returns null.
  static String? _extractEntityName(String title) {
    final match = RegExp(r'[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*').firstMatch(title);
    return match?.group(0);
  }

  /// Naive stem: lowercase, collapse whitespace, strip a trailing `s`
  /// off each word so "Customers" and "Customer" collapse to the same
  /// key. The strip is intentionally simple — "is" / "as" / "bus" are
  /// not protected, but those words never appear as entity stems in a
  /// real SRS, and a rare false positive on a name like "Bus" is a
  /// cheaper failure mode than missing the cross-section variant.
  static String _stem(String name) {
    final words = name.toLowerCase().split(RegExp(r'\s+'));
    return words
        .map(
          (w) => (w.length > 1 && w.endsWith('s'))
              ? w.substring(0, w.length - 1)
              : w,
        )
        .join(' ');
  }
}

class _Cluster {
  _Cluster({required this.originals, required this.sections});
  final Set<String> originals;
  final Set<String> sections;
}
