/// Auto-selects which requirements get their page image attached.
///
/// Roadmap M4: "Auto-select từ layout/caption/labels; preview danh sách cho
/// user sửa". This is that selection step, v0: the diagram-intent detector
/// gates on the requirement text, the document's inferred image pages supply
/// the candidates, and the run-wide [ImageBudget] bounds how many distinct
/// pages may ride. The output is a per-requirement plan — the list a preview
/// UI would let the user correct later.
///
/// Gate order is deliberate and cheap-first:
///   1. text intent   — most requirements have none; nothing is reserved.
///   2. candidate     — intent without a page reference has nothing to attach.
///   3. budget        — only reached for a real candidate, so "budget spent"
///                      never masks a requirement that could not ship an
///                      image anyway. Overrun defers (text-only), it never
///                      fails the run nor downsamples beyond legibility.
///
/// Bytes never flow through here — this layer plans, the renderer (not yet
/// chosen; see the renderer spike) produces bytes for pages marked
/// [PageImageDecision.selected]. Coverage log discipline applies: every
/// decision records a stable reason token, and no log line ever carries
/// image data.
library;

import '../checks/diagram_detector.dart';
import '../models/document_blueprint.dart';
import 'image_budget.dart';

/// What the run would do with a requirement's page image.
enum PageImageDecision {
  /// Diagram intent, a candidate page, and budget to spare. The page is
  /// reserved by the time this plan is returned.
  selected,

  /// No diagram signal in the text — text-only review, nothing reserved.
  skippedNoDiagramIntent,

  /// Intent present, but the requirement has no page reference or its page
  /// is not one the parser flagged as holding an image.
  skippedNoCandidatePage,

  /// Intent and candidate, but the run's image budget is spent. Deferred to
  /// text-only — recorded so the user can tell a budget cutoff apart from a
  /// page with no diagram.
  deferredBudgetSpent,
}

/// One requirement's outcome, with the reason token a coverage log needs.
///
/// [reason] is null exactly when the decision is [PageImageDecision.selected];
/// every non-selection names why, from the fixed token set below.
class PageImagePlan {
  const PageImagePlan._(
    this.requirementId,
    this.pageIndex,
    this.decision,
    this.reason,
  );

  /// The caller's identity for the requirement (occurrence key in the run
  /// loop); opaque here.
  final String requirementId;

  /// The page the plan concerns, when one exists.
  final int? pageIndex;

  final PageImageDecision decision;

  /// Stable token: 'no-diagram-intent' | 'no-candidate-page' | 'budget-spent'.
  final String? reason;

  @override
  String toString() =>
      'PageImagePlan($requirementId, page: $pageIndex, $decision, reason: $reason)';
}

/// Plans page-image attachments for one review run.
///
/// Stateful only through [ImageBudget]: reservations accumulate across calls,
/// which is the point — first-come-first-served within the bounded
/// concurrency the repository runs. Requirements sharing a page share one
/// reservation ([ImageBudget.canAttach]), so a diagram cited by five
/// requirements costs one budget slot, not five.
class PageImageSelector {
  PageImageSelector({
    DiagramDetector detector = const DiagramDetector(),
    required this.budget,
    // Named initializing formals cannot target a private field, so this
    // assignment has to stay explicit.
    // ignore: prefer_initializing_formals
  }) : _detector = detector;

  final DiagramDetector _detector;
  final ImageBudget budget;

  /// Decides and (on selection) reserves in one step, so a plan can never
  /// claim a page the budget did not record.
  ///
  /// [blueprint] lets a requirement that names a figure ("see Figure 12")
  /// attach the page that figure actually lives on, instead of only the page
  /// the requirement itself sits on. Without an index, behaviour is unchanged.
  PageImagePlan planFor({
    required String requirementId,
    required String text,
    int? pageIndex,
    required Set<int> candidatePages,
    DocumentBlueprint? blueprint,
  }) {
    final signal = _detector.detectWithBlueprint(text, blueprint);
    if (!signal.hasIntent) {
      return PageImagePlan._(
        requirementId,
        pageIndex,
        PageImageDecision.skippedNoDiagramIntent,
        'no-diagram-intent',
      );
    }
    // A named figure resolves to its own page; that page outranks the page the
    // requirement happens to be printed on.
    final effectivePage = signal.resolvedPageIndex ?? pageIndex;
    if (effectivePage == null || !candidatePages.contains(effectivePage)) {
      return PageImagePlan._(
        requirementId,
        effectivePage,
        PageImageDecision.skippedNoCandidatePage,
        'no-candidate-page',
      );
    }
    if (!budget.tryReserve(effectivePage)) {
      return PageImagePlan._(
        requirementId,
        effectivePage,
        PageImageDecision.deferredBudgetSpent,
        'budget-spent',
      );
    }
    return PageImagePlan._(
      requirementId,
      effectivePage,
      PageImageDecision.selected,
      null,
    );
  }
}
