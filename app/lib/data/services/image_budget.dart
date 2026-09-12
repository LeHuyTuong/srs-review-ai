/// Per-run page-image budget for the review loop.
///
/// Why a budget at all: the run cap is now 60 requirements, and a document
/// where every requirement cites a figure would otherwise rasterize and ship
/// up to 60 page images — against a proxy that bounds each /review payload
/// and a free-tier Gemini quota. The guard keeps the run honest: the FIRST
/// time a page is asked for it is reserved, later requirements on the same
/// page share that reservation, and once the budget is spent the run
/// degrades gracefully to text-only review instead of failing.
///
/// The budget is deduplication-plus-ceiling, not a cache: it tracks
/// *reservations*, not image bytes.
library;

/// Roadmap M4: "Budget 12 trang chỉ là mặc định thử nghiệm, không phải mức
/// đã đo" — an experimental default, not a measured one. Callers that know
/// better (a measured usage profile, a paid quota tier) should pass their
/// own [ImageBudget.maxPages]; this constant exists only so a run without
/// configuration still degrades instead of ballooning.
const int kRoadmapDefaultMaxPageImages = 12;

/// Reserves distinct page images across one review run.
class ImageBudget {
  /// A runtime guard, not an assert: asserts are stripped from release
  /// builds, and a silently negative budget would just never be spent.
  ImageBudget({int? maxPages})
      : maxPages = maxPages ?? kRoadmapDefaultMaxPageImages {
    if (this.maxPages < 0) {
      throw ArgumentError.value(
          maxPages, 'maxPages', 'a budget of ${this.maxPages} pages cannot be spent');
    }
  }

  /// The ceiling this run chose — surfaced in findings so a user can tell a
  /// budget cutoff apart from a page that genuinely has no image.
  final int maxPages;

  final Set<int> _reserved = {};

  /// How many distinct pages are currently reserved.
  int get used => _reserved.length;

  /// True once every reservation is spent.
  bool get isExhausted => _reserved.length >= maxPages;

  /// Whether requirements on [pageIndex] may ship their page image.
  ///
  /// A null page index (requirement not tied to a page) is always free: the
  /// text-only path costs nothing to guard.
  bool canAttach(int? pageIndex) {
    if (pageIndex == null) return true;
    if (_reserved.contains(pageIndex)) return true;
    return _reserved.length < maxPages;
  }

  /// Reserves [pageIndex]; returns false — and reserves nothing — when the
  /// budget is already spent. Reserve only pages you are about to use.
  bool tryReserve(int pageIndex) {
    if (!canAttach(pageIndex)) return false;
    _reserved.add(pageIndex);
    return true;
  }
}
