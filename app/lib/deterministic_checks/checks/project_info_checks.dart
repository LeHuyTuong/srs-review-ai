/// §F.3/F.4 (rulebook 1.7-draft) — the two checks that need something the
/// document cannot tell us about itself.
///
/// §F.3 compares the user's declaration (`contracts/project-info.schema.json`)
/// against what the cover page actually prints: the document may claim to be
/// one project while its cover says another, and no amount of reading the
/// file alone can see that mismatch — only a human declaration can. §F.4
/// reads the resolved chapter ranges and reports a chapter that starts before
/// its predecessor ended: a chapter is misplaced or the index lies.
///
/// Both deterministic, zero tokens, no OCR: unreadable pages fall silent
/// (hard rule 3) exactly like the other furniture checks.
library;

import '../../document_import/models/document_blueprint.dart';
import '../../document_import/models/project_info.dart';
import '../../requirement_review/models/review_models.dart' show Severity;
import '../models/deterministic_finding.dart';
import 'text_fold.dart';

class ProjectInfoChecks {
  const ProjectInfoChecks();

  // ----------------------------------------------------- §F.3 declaredVsCover

  /// How much of a single-entry (DOCX) document the cover check may read —
  /// the same 2000-char head §F.1 defines.
  static const int _docxCoverChars = 2000;

  /// Tokens shorter than this are stop-words and acronym fragments: matching
  /// them proves nothing ("the", "an", "SRS").
  static const int _minTitleTokenChars = 4;

  /// Below this share of the declared title's tokens appearing on the cover,
  /// the declaration is reported. 50% tolerates rewording; it does not
  /// tolerate a different project.
  static const double _titleTokenFloor = 0.5;

  /// §F.1's cover region, duplicated on purpose rather than shared: a check
  /// file that reaches into another check's private helper couples two
  /// families that are versioned separately in the rulebook.
  static String _coverText(List<String> pageTexts) {
    if (pageTexts.isEmpty) return '';
    if (pageTexts.length == 1) {
      final only = pageTexts.single;
      return only.length <= _docxCoverChars
          ? only
          : only.substring(0, _docxCoverChars);
    }
    return '${pageTexts[0]}\n${pageTexts[1]}';
  }

  /// One finding per field the cover fails to confirm. Empty when nothing was
  /// declared — the form is optional, and "did not fill the form" must never
  /// read as a defect of the document.
  List<DeterministicFinding> declaredVsCover(
    ProjectInfo declared,
    List<String> pageTexts,
  ) {
    final cover = _coverText(pageTexts);
    // Fewer than 3 readable lines: a scanned cover, nothing to compare
    // against — stay silent (same rule as §F.1).
    final lines = cover.split('\n').where((l) => l.trim().isNotEmpty).length;
    if (lines < 3) return const [];
    final foldedCover = foldVietnamese(cover);

    final findings = <DeterministicFinding>[];
    final titleTokens = foldVietnamese(
      declared.projectName,
    ).split(' ').where((token) => token.length >= _minTitleTokenChars).toSet();
    if (titleTokens.isNotEmpty) {
      final matched = titleTokens
          .where((token) => foldedCover.contains(token))
          .length;
      if (matched / titleTokens.length < _titleTokenFloor) {
        findings.add(
          DeterministicFinding(
            check: CheckId.projectInfoMismatch,
            passed: false,
            severity: Severity.high,
            subject: 'title',
            messageEn:
                'The declared project title "${declared.projectName}" barely '
                'appears on the cover page ($matched/'
                '${titleTokens.length} keywords matched). Check whether the '
                'cover states the right title, or the declared name is '
                'abbreviated. Heuristic over extracted text — verify visually.',
            messageVi:
                'Tên đề tài khai báo "${declared.projectName}" hầu như không '
                'xuất hiện trên trang bìa (khớp $matched/'
                '${titleTokens.length} từ khoá). Kiểm tra xem bìa có ghi '
                'đúng đề tài không, hoặc tên khai báo đang viết tắt. '
                'Heuristic trên text trích xuất — đối chiếu bằng mắt.',
          ),
        );
      }
    }

    final supervisor = declared.supervisor;
    if (supervisor != null && supervisor.trim().isNotEmpty) {
      final foldedSupervisor = foldVietnamese(supervisor).trim();
      if (!foldedCover.contains(foldedSupervisor)) {
        findings.add(
          DeterministicFinding(
            check: CheckId.projectInfoMismatch,
            passed: false,
            severity: Severity.medium,
            subject: 'supervisor',
            messageEn:
                'The declared supervisor "$supervisor" was not found on the '
                'cover page. Check whether the cover names a supervisor at '
                'all, or spells the name differently from the declaration. '
                'Heuristic over extracted text — verify visually.',
            messageVi:
                'Tên giảng viên hướng dẫn khai báo "$supervisor" không thấy '
                'trên trang bìa. Kiểm tra xem bìa có ghi GVHD chưa, hoặc tên '
                'trên bìa viết khác với khai báo. Heuristic trên text trích '
                'xuất — đối chiếu bằng mắt.',
          ),
        );
      }
    }

    return findings;
  }

  // -------------------------------------------------------- §F.4 sectionOrder

  /// Chapters must advance through the document. A chapter whose printed
  /// start page sits before its predecessor's printed end means the index is
  /// lying or the chapter is physically misplaced — either way the reader
  /// cannot trust the outline.
  ///
  /// Gated on [DocumentBlueprint.trusted], same as `captionPageMismatch`:
  /// with an untrusted index the ranges are guesses, and a guess must not
  /// produce a finding.
  List<DeterministicFinding> sectionOrder(DocumentBlueprint? blueprint) {
    if (blueprint == null || !blueprint.trusted) return const [];
    final sections = blueprint.sections;
    final findings = <DeterministicFinding>[];
    for (var i = 1; i < sections.length; i++) {
      final previous = sections[i - 1];
      final current = sections[i];
      if (current.printedStart >= previous.printedEnd) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.sectionOrder,
          passed: false,
          severity: Severity.medium,
          subject: '${previous.id}->${current.id}',
          messageEn:
              'Section "${previous.id} ${previous.title}" runs to printed '
              'page ${previous.printedEnd}, but section '
              '"${current.id} ${current.title}" starts at printed page '
              '${current.printedStart} — the sections overlap or are out of '
              'order. Check the index and the chapter placement in the '
              'printed document.',
          messageVi:
              'Phần "${previous.id} ${previous.title}" trải tới trang in '
              '${previous.printedEnd}, nhưng phần "${current.id} ${current.title}" '
              'bắt đầu từ trang in ${current.printedStart} — các phần chồng '
              'lên nhau hoặc sai thứ tự. Kiểm tra mục lục và vị trí chương '
              'trong bản in.',
        ),
      );
    }
    return findings;
  }

  /// Both checks in one call, for callers that hold a document in hand.
  List<DeterministicFinding> runAll({
    ProjectInfo? declared,
    required List<String> pageTexts,
    DocumentBlueprint? blueprint,
  }) => [
    if (declared != null) ...declaredVsCover(declared, pageTexts),
    ...sectionOrder(blueprint),
  ];
}
