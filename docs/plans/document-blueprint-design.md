# DocumentBlueprint — Thiết kế chi tiết (TOC-Driven Review Engine)

> Trạng thái: **Design proposal** (chưa code). Bối cảnh: audit 2026-09-21 (team 3 agent)
> phát hiện parser 1.2.0 đã parse TOC (`table_of_contents.dart`) nhưng **vứt ngay sau
> khi tách requirement** — Figures của LoF không đi tới vision, không check nào chạy
> trên mục lục. Tài liệu này định nghĩa `DocumentBlueprint` để khép gap đó.
>
> Kiểm chứng: `app/tool/verify_sample_srs.dart` (flutter test, 2026-09-21) — Part A
> parse `sample_srs.docx` thật (DOCX → TOC rỗng → fallback đúng); Part B fixture TOC
> kiểu đồ án FPTU → `TableOfContents.parse` bắt đủ 19 entries, mini blueprint checks
> phát hiện 3 cụm trùng tên UC + đứt số Figure 39→41 với 0 token.

## 1. Nguyên tắc thiết kế

1. **Blueprint là dữ liệu, không phải check.** Mọi suy luận (offset, range, loại sơ
   đồ) nằm trong builder; mọi đánh giá nằm trong `BlueprintChecks`. Tách hai thứ để
   test độc lập.
2. **Không bao giờ làm tệ hơn hiện trạng.** Không build được blueprint → `null` →
   toàn bộ hành vi cũ (body scan, heuristic mật độ chữ) giữ nguyên. DOCX luôn `null`
   (không có khái niệm trang — đã kiểm chứng Part A).
3. **Fallback chỉ rơi units, không rơi blueprint.** Sửa G5: khi
   `_tocConfidenceRatio` khiến splitter chọn body-units, blueprint vẫn được đính kèm
   `SrsDocument`.
4. **Pure Dart, no I/O** cho builder/checks (theo convention `requirement_splitter.dart`,
   `table_of_contents.dart`) — unit-testable 100%.

## 2. Data model

File mới: `app/lib/data/models/document_blueprint.dart`

```dart
/// Loại sơ đồ suy ra từ caption trong List of Figures (0 token).
enum DiagramKind {
  useCase, sequence, classDiagram, activity, erd,
  component, architecture, wireframe, communication, physical, unknown,
}

/// Một dòng trong List of Tables / List of Figures, đã resolve vị trí thật.
class ArtifactRef {
  const ArtifactRef({
    required this.kind,            // TocEntryKind.table | figure
    required this.number,          // Table 9 -> 9
    required this.caption,         // caption gốc đã clean
    required this.normalizedCaption, // lower, bỏ 'use case', bỏ <Actor>, non-alnum
    required this.printedPage,     // trang in trong mục lục (1-based)
    required this.pdfPageIndex,    // 0-based index vào pageTexts; null nếu không resolve được
    this.diagramKind,              // chỉ figure; unknown nếu caption không phân loại được
    this.sectionId,                // 'C' | 'D' | ... — section chứa artifact
  });
}

/// Một chapter/section với RANGE đầy đủ (sửa G4: hiện chapterForPage chỉ có START).
class SectionRange {
  const SectionRange({
    required this.id,              // 'A'..'G' (hoặc '1', '2' cho TOC dạng số)
    required this.title,           // 'Software Requirement Specification'
    required this.printedStart,
    required this.printedEnd,      // = printedStart của chapter kế - 1
    required this.pdfStartIndex,
    required this.pdfEndIndex,
  });

  bool containsIndex(int pdfPageIndex) =>
      pdfPageIndex >= pdfStartIndex && pdfPageIndex <= pdfEndIndex;
}

class DocumentBlueprint {
  const DocumentBlueprint({
    required this.sections,
    required this.artifacts,
    required this.pageOffset,      // pdfIndex = printedPage - 1 + pageOffset
    required this.tocPageIndexes,  // các trang mục lục (để body scan skip)
    required this.trusted,         // false → consumer chỉ dùng làm hint
  });

  Iterable<ArtifactRef> get tables;
  Iterable<ArtifactRef> get figures;
  SectionRange? sectionOf(int pdfPageIndex);

  /// Convenience cho syllabus scoping: section có title match
  /// /software requirement specification|srs/i (sửa G4 — check chạy trong range
  /// phần C thay vì toàn tài liệu).
  SectionRange? get srsSection;
}
```

`SrsDocument` thêm field (sửa G3):

```dart
final DocumentBlueprint? blueprint; // null với DOCX / PDF không có TOC
```

→ bump `kParserVersion = '1.3.0'` (`srs_document.dart:21`) vì occurrence identity có
thể đổi khi units lấy section từ blueprint.

## 3. BlueprintBuilder — thuật toán build

File mới: `app/lib/data/parsing/blueprint_builder.dart`

```
build(pageTexts, toc) -> DocumentBlueprint?
```

| Bước | Việc | Chi tiết & biên |
|---|---|---|
| B0 | Gate | `toc.isEmpty` → null. Cần ≥1 chapter HOẶC (≥3 table/figure entries) |
| B1 | Normalize caption | `lower → bỏ <Actor> → bỏ prefix 'use case' → non-alnum→space → trim`. Đã kiểm chứng gom đúng 3 cụm trùng tên (Part B) |
| B2 | Hiệu chỉnh offset | Với mỗi chapter: tìm title (folded) trong body pages → ứng viên `offset_i = pdfIndex - (printedPage - 1)`. Offset = mode của các ứng viên; mâu thuẫn → `offset=0, trusted=false`. Xử lý front-matter La Mã (i–x) |
| B3 | Resolve pdfPageIndex | `printedPage - 1 + offset`, clamp vào [0, pageCount). **Verify**: trang đích phải chứa ≥30 ký tự đầu của caption (folded); không khớp → tìm trang gần nhất chứa caption (±3), vẫn không → `pdfPageIndex=null` (hint-only) |
| B4 | Section ranges | Sắp chapter theo printedPage; end = start kế − 1; chapter cuối end = pageCount. Convert qua offset |
| B5 | Classify figure | Caption folded contains: 'class diagram'→classDiagram; 'sequence'→sequence; 'activity'→activity; 'erd'/'entity relationship'→erd; 'use case'/'overview use case'→useCase; 'component'→component; 'architecture'→architecture; 'interface'/'mockup'/'wireframe'→wireframe; 'communication'→communication; 'physical'→physical; else unknown. (Part B kiểm chứng: Figure 75→classDiagram@160, 90→erd@180) |
| B6 | Gán sectionId | `sections.firstWhere((s) => s.containsIndex(pdfPageIndex))` |

**Regex nâng cấp cần thêm vào `table_of_contents.dart`:**
- `_chapter` hiện chỉ nhận 1 chữ cái `[A-Z]` (dòng 121-123) → mở rộng:
  `^([A-Z]|\d+(?:\.\d+)*)[.)]\s+(\S.*?)\s*[\t\s.·]*?(\d{1,4})\s*$`
  (nhận cả TOC dạng số `1.2 Problem Abstract … 14`).
- `_numbered` thêm `\t` tường minh trong cụm leader (đã match nhờ `\s`, viết tường
  minh để không phụ thuộc hành vi ngầm).

## 4. BlueprintChecks — check 0-token chạy lúc load

File mới: `app/lib/data/checks/blueprint_checks.dart`. Output là
`DeterministicFinding` với `CheckId` mới (thêm vào enum
deterministic_finding.dart:9): `duplicateCaption`, `numberingGap`,
`missingSection`, `unclassifiedFigure`, `captionPageMismatch`.

| # | Check | Logic | Severity | Ghi chú từ kiểm chứng |
|---|---|---|---|---|
| C1 | duplicateCaption | Group tables theo `normalizedCaption`; >1 → 1 finding liệt kê mọi số Table + trang | medium | Part B: bắt đúng 3 cụm (Table 22/23, 40/42/43, 48/50) — đây là lỗi copy-paste ẩu kinh điển của đồ án |
| C2 | numberingGap | Trong mỗi kind, sort theo number; gap >1 → finding | low | **Hiệu chỉnh sau khi chạy thật:** fixture thưa sinh nhiễu (9→22, 42→75 là gap giả do fixture là subset). Rule chống nhiễu: chỉ flag khi gap ≤ 3 VÀ cả hai entry cùng `sectionId`; gap lớn giữa hai section (LoF chuyển chương) là bình thường |
| C3 | missingSection | Khung A–F kỳ vọng (Introduction / PM Plan / SRS / SDD / Test / User Manual) so với `sections`; thiếu → finding kèm tên phần thiếu | high nếu thiếu C (SRS), medium nếu thiếu phần khác | Port luật missingSection của rulebook (hiện chưa có — workflow-auditor finding #6) |
| C4 | unclassifiedFigure | `diagramKind == unknown` → gợi ý đặt caption rõ loại sơ đồ | low | Không chặn, chỉ tư vấn |
| C5 | captionPageMismatch | Entry có `pdfPageIndex == null` hoặc verify thất bại ở B3 | low | Phát hiện mục lục cũ chưa update sau khi sinh viên sửa bài — rất hay gặp |

Tất cả chạy **một lần lúc load document**, cùng chỗ `SyllabusChecks.runAll`
hiện được gọi — người dùng thấy lỗi mục lục NGAY trước khi bấm AI Review.

## 5. Điểm tích hợp (file chạm tới)

| File | Thay đổi |
|---|---|
| `data/models/srs_document.dart` | + `blueprint` field; `kParserVersion` → `1.3.0` |
| `data/models/document_blueprint.dart` | **MỚI** — model mục 2 |
| `data/parsing/blueprint_builder.dart` | **MỚI** — mục 3 |
| `data/parsing/table_of_contents.dart` | Nâng `_chapter`/`_numbered` regex (B7); export thêm figures với caption |
| `data/parsing/requirement_splitter.dart` | `_splitByToc`/fallback đều trả kèm blueprint (sửa G5); `_tocLine` giữ nguyên cho DOCX |
| `data/services/parse_service.dart` | `PdfParser`/`DocxParser` gọi builder; DOCX truyền null thẳng |
| `data/checks/blueprint_checks.dart` | **MỚI** — mục 4 |
| `data/services/page_image_selector.dart` + `vision_review_service.dart` | Candidate pages + DiagramKind lấy từ `blueprint.figures` khi trusted; heuristic mật độ chữ (`parse_service.dart:182-193`) chỉ còn là fallback khi blueprint=null |
| `data/checks/diagram_detector.dart` | Nếu text chứa `Figure N` và blueprint có figure N → intent chắc chắn + biết trang đích (không cần quét candidate) |
| `data/checks/syllabus_checks.dart` | Khi có `srsSection`: F7/F9 đếm trong range phần C (sửa G4) |
| `features/workspace/.../loaded_document.dart` | + `blueprintFindings` cạnh `findings`/`referenceFindings`; UI ledger thêm nhóm "Mục lục" |
| `features/workspace/view/inventory_tab.dart` (hoặc Master-Detail mới) | Cây section render từ `blueprint.sections` + chấm severity per section |

## 6. Rủi ro & giảm thiểu (đã cập nhật sau khi chạy thật)

| # | Rủi ro | Giảm thiểu |
|---|---|---|
| R1 | TOC không có số trang (Word xuất thô) | `_numbered` bắt buộc page → parse rỗng → blueprint=null, fallback caption-search trong body |
| R2 | TOC heading-style không dotted leader | Điều kiện trang chứa 'list of tables|list of figures|danh mục|mục lục' để định vị trang mục lục thay vì chỉ đếm ≥3 dòng |
| R3 | PDF scan | Đã từ chối sớm (`isScannedPdf`, parse_service.dart:159-165); không vi phạm quyết định no-OCR |
| R4 | Lệch offset front-matter (i–x) | B2 mode-of-candidates; mâu thuẫn → trusted=false |
| R5 | Caption nhiễu (số trang dính title, 'Version 2.0 … 25') | `_clean` + kiểm title có chữ cái (table_of_contents.dart:199-200) đã lọc phần lớn; C1 group theo normalizedCaption tự khử biến thể whitespace |
| R6 | DOCX | blueprint=null — đã kiểm chứng Part A (toc.entries=0, fallback body scan đúng, 8 units) |
| R7 | **Numbering-gap nhiễu trên LoT/LoF thưa hoặc nhiều chương** (phát hiện khi chạy Part B: 8 finding gap trong đó chỉ 1 là thật) | Rule gap ≤ 3 + cùng sectionId (C2); nếu blueprint không trusted → tắt C2 hoàn toàn |

## 7. Test plan

1. **Unit — builder:** fixture 3 trang mục lục (đã có trong `verify_sample_srs.dart`
   Part B) → assert 19 entries, offset, ranges C=22..154; fixture front-matter La Mã;
   fixture caption nhiễu; DOCX → null.
2. **Unit — checks:** C1 bắt đúng 3 cụm; C2 chỉ flag 39→41 (không flag 42→75 khác
   section); C3 thiếu phần C → high; C5 entry không resolve được.
3. **Golden:** chạy `dump_page_text.dart` + blueprint trên PDF đồ án thật (env
   `SRS_TEST_PDF` — convention sẵn có) → snapshot số artifact/section.
4. **Regression:** toàn bộ test hiện có (`requirement_splitter_test.dart`,
   `parse_service_test.dart`, `syllabus_checks_test.dart`…) phải xanh với DOCX và
   PDF không TOC — chứng minh nguyên tắc 2.
5. **Probe giữ lại:** `tool/verify_sample_srs.dart` chuyển thành test thường trực
   sau khi blueprint land (đổi print → expect).

## 8. Giá trị đo được (từ lần chạy kiểm chứng 2026-09-21)

- Với mục lục đồ án FPTU mẫu: **≥5 lỗi thật** (3 cụm trùng tên UC, đứt Figure 40,
  và C5 khi mục lục lệch trang) phát hiện với **0 token Gemini, <10ms**.
- Vision audit: từ "quét mọi trang <120 ký tự" → "đúng 6 trang có figure, biết sẵn
  loại sơ đồ" → giảm số ảnh gửi lên `/diagram`, tăng precision của DiagramKind.
- F7/F9 scope đúng phần C: không còn đếm lẫn bảng của phần D (SDD) / E (Test).

---

# Implementation notes — 2026-09-21

Đã implement xong 3 phần lõi + test. Mục này ghi lại các quyết định THỰC TẾ khi code,
những chỗ lệch so với thiết kế ban đầu và lý do.

## Files

| File | Trạng thái |
|---|---|
| `app/lib/data/models/document_blueprint.dart` | **MỚI** — `DocumentBlueprint`, `SectionRange`, `ArtifactRef`, `ArtifactKind` |
| `app/lib/data/parsing/blueprint_builder.dart` | **MỚI** — `BlueprintBuilder`, `normalizeCaption`, `diagramKindForCaption`, `foldText` |
| `app/lib/data/checks/blueprint_checks.dart` | **MỚI** — `BlueprintChecks` (5 check) |
| `app/lib/data/models/srs_document.dart` | + `blueprint` (nullable, không tham gia `documentFingerprint`) |
| `app/lib/data/models/deterministic_finding.dart` | + 5 `CheckId` + wire + label + `isBlueprintCheck` |
| `app/lib/data/parsing/table_of_contents.dart` | `_chapter` nhận cả dạng số `1.2 …` ngoài `C. …` |
| `app/lib/data/parsing/requirement_splitter.dart` | `split(pageTexts, {toc})` — dùng lại index đã parse |
| `app/lib/data/services/parse_service.dart` | PDF: parse TOC 1 lần → splitter + blueprint; DOCX: blueprint null |
| `app/lib/features/workspace/view/workspace_modals.dart` | + `_rule`/`_fix` tiếng Việt cho 5 check mới |
| `app/lib/features/workspace/view/workspace_widgets.dart` | + 5 nhãn tiếng Việt |
| `contracts/review.schema.json` | + 5 wire mới vào enum |
| `app/test/document_blueprint_test.dart` | **MỚI** — 14 test model + CheckId contract |
| `app/test/blueprint_builder_test.dart` | **MỚI** — 17 test builder |
| `app/test/blueprint_checks_test.dart` | **MỚI** — 19 test checks |
| `app/tool/verify_sample_srs.dart` | + Part C chạy builder + checks end-to-end |

## Quyết định khác thiết kế ban đầu

1. **KHÔNG bump `kParserVersion`.** Thiết kế dự kiến 1.3.0, nhưng khi code thì splitter
   vẫn cho ra ĐÚNG units như trước (TOC được truyền vào thay vì parse lại — cùng kết quả,
   chỉ rẻ hơn), và blueprint là **dữ liệu dẫn xuất** không tham gia occurrence key hay
   fingerprint. Bump version sẽ vô hiệu hoá session/snapshot đã lưu mà không có lý do.
   Chỉ bump khi units hoặc cách keying thay đổi thật.
2. **Tái dùng `DiagramKind` có sẵn** (`checks/diagram_type_classifier.dart`) thay vì tạo
   enum mới. Enum đó ánh xạ 1-1 với `DiagramType` của server (`/diagram` là Pydantic
   StrEnum) — thêm kind mới là phá contract. Caption classifier vì vậy chỉ trả về các
   giá trị server đã biết (architecture/wireframe → `component`, không có member riêng).
3. **Thứ tự probe khi resolve trang: NHÃN trước, CAPTION sau.** Thiết kế chỉ nói "verify
   caption". Chạy probe thật thì lộ ra: hai artifact trùng caption (Table 22/23 "Kick a
   student out of group") khiến caption-probe gửi cả hai về cùng một trang. Khớp theo
   nhãn in (`table 23`, regex có `(?![0-9])` để `table 230` không khớp) phân biệt được,
   và vẫn giữ caption-probe làm fallback cho tài liệu bị flatten mất số.
4. **Trang mục lục không bao giờ được nhận làm trang artifact.** Test phát hiện window
   search có thể đi ngược lên trang LoT/LoF (trang đó chứa mọi caption) và trả về một
   trang chỉ có con trỏ. Đây là bug thật, đã fix + có regression test.
5. **C2 (numberingGap) KHÔNG gate theo `trusted`.** Thiết kế dự kiến tắt khi blueprint
   không trusted, nhưng check này chỉ dùng số in + section, không dùng `pdfPageIndex`,
   nên không phụ thuộc mapping trang. Nhiễu được chặn bằng đúng luật đã đo: gap ≤ 3 VÀ
   cùng section. C5 (captionPageMismatch) thì vẫn gate theo `trusted` — nó kết luận về
   *trang*, nên chỉ được nói khi mapping đã verify.
6. **5 check mới KHÔNG vào `floorCriteria`** (thang điểm E). Chúng là lỗi cấu trúc mục
   lục, không thuộc 7 tiêu chí IEEE-830 của sàn 5 điểm. Thêm vào sẽ đổi điểm số của
   tài liệu thật mà không có căn cứ rubric — để riêng, hiển thị dưới nhóm "Mục lục"
   nhờ `CheckId.isBlueprintCheck`.

## Việc CHƯA làm (giữ đúng phạm vi Sprint 2 item 5)

Các điểm tích hợp còn lại của thiết kế §5, để dành cho bước sau:

- Vision: `page_image_selector` / `vision_review_service` dùng `blueprint.figures` thay
  heuristic mật độ chữ (`parse_service.dart:182`). Hiện blueprint đã sẵn sàng trên
  `SrsDocument`, chỉ cần consumer.
- `SyllabusChecks` scope F7/F9 vào `blueprint.srsSection` thay vì toàn tài liệu.
- `LoadedDocument.blueprintFindings` + nhóm "Mục lục" trên ledger/UI, cây section
  Master-Detail.

## Kiểm chứng

- `flutter test test/document_blueprint_test.dart test/blueprint_builder_test.dart test/blueprint_checks_test.dart`
  → **50/50 pass**.
- `flutter analyze lib test` → 0 error, 0 warning (1 info có sẵn ở
  `requirement_splitter.dart:152`).
- `flutter test` toàn bộ → **642 pass, 2 fail**, cả hai KHÔNG do thay đổi này:
  1. `requirement_splitter_test.dart: extracts ids and normalises them to two digits` —
     test cũ còn kỳ vọng zero-padding `FR-01`, parser 1.2.0 đã cố tình giữ `FR-1`.
  2. `workspace_view_model_test.dart: a run whose units all failed reports the failures,
     not zero` — nhánh `reviewed == 0` mới thêm trong WIP chưa commit của
     `workspace_view_model.dart:831` giờ set `error` và return sớm, nên toast
     "… failed and were NOT reviewed" không còn được tạo. Test cần cập nhật theo hành vi mới.
- `flutter test tool/verify_sample_srs.dart` — Part A (DOCX thật), B (index fixture),
  C (builder + checks end-to-end): 3/3 pass.

7. **Không fix cứng khung báo cáo (phản hồi review 2026-09-21).** Điểm dự
   kiến của thiết kế là khung A–F cố định trong code. Đã sửa: `ExpectedSection`
   là kiểu public const, `BlueprintChecks(expectedSections: ..., maxGap: ...)` nhận
   khung qua constructor (mặc định `defaultExpectedSections` phản ánh một khung
   capstone, không phải học thuyết bất biến), và `missingSections` có
   **frame-gate**: chỉ chấm khi tài liệu thể hiện được khung đó — ngưỡng
   là `min(2, half(frame))`, tức khung 5 phần cần ≥2 phần khớp mới bật, khung
   2 phần thì 1 phần khớp đã đủ. Tài liệu theo cấu trúc riêng (không
   phần nào khớp) bị bỏ qua hoàn toàn thay vì bị báo "thiếu 5 phần".
   Lưu ý: **section ranges không bao giờ fix cứng** — builder suy ra hoàn toàn
   từ TOC của chính tài liệu (start/end theo chapter thật, offset hiệu chỉnh
   theo front-matter thật); dải `22–154` trong phần ví dụ là dữ liệu của
   một report cụ thể, không nằm trong code.

8. **Hoàn tất phần tích hợp còn lại của §5 (cùng ngày).** Tất cả consumer của
   blueprint đã được nối:
   - **Vision targeting**: `VisionReviewService.candidates` dùng nhánh mới
     `_candidatesFromBlueprint` khi `SrsDocument.blueprint` tồn tại — mỗi
     figure đã resolve là một candidate với `DiagramKind` lấy từ caption
     (known-first, unknown sau, rồi orphan image pages); heuristic mật độ chữ
     chỉ còn là fallback khi không có index. `DiagramDetector` thêm
     `detectWithBlueprint` (regex `Figure N` → `resolvedPageIndex`),
     `PageImageSelector.planFor` dùng trang figure đã resolve thay trang của
     requirement, `review_repository` gom candidate pages từ cả
     `imagePageIndexes` lẫn `blueprint.figures`.
   - **Syllabus scoping**: `SyllabusChecks.srsScopedRequirements` — khi có
     `srsSection`, F7 (đếm UC) và F9 (kích thước UC) chỉ đếm yêu cầu trong
     phạm vi phần C; F8 và quality checks giữ toàn tài liệu (ngôn ngữ là luật
     document-wide). Không index → hành vi cũ nguyên vẹn.
   - **LoadedDocument + UI + exports**: `LoadedDocument.blueprintFindings`,
     `WorkspaceState.blueprintFindings`, persist/restore qua snapshot key
     `blueprintFindings`, nhóm "Mục lục (document index)" trên SyllabusTab,
     family label "document index" trong markdown/JSON/HTML exports, và
     `Verifier.verify(blueprintFindings: ...)` để re-review ledger hoạt động
     cho cả index findings.
   - **2 test fail có sẵn được chữa**: `requirement_splitter_test` cập nhật
     theo hành vi 1.2.0 (giữ nguyên digits `FR-1`, không pad `FR-01`);
     `workspace_view_model_test` cập nhật theo nhánh WIP `reviewed == 0`
     (error banner thay success toast).
   - Kết quả: **`flutter test` 657/657 pass, `flutter analyze lib test` 0
     error / 0 warning** (1 info có sẵn ở `requirement_splitter.dart:152`).
