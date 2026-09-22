# Review: "chỉ nhận mỗi use case, các phần SRS khác không nhận gì" — 2026-09-21

## Addendum 2 (2026-09-22) — footer bị đọc thành heading, thân UC bị cắt

Sau lượt chấm AI thật đầu tiên trên parser 1.4.1 (240 unit), snapshot cho thấy
unit UC trung bình chỉ ~321 ký tự, ngắn nhất 20. Đo lại bằng probe trên đúng
file OTES 217 trang:

| | 1.4.0 (extractText) | 1.4.1 (joinVisualLines) | sau fix |
|---|---|---|---|
| unit / UC | 85 / 85 | 235 / 63 | **130 / 63** |
| UC có "Main success scenario" | — | **9/63** | **63/63** |
| UC dài nhất | 33 825 (nuốt cả tài liệu) | 1 026 | 1 944 |
| section là thân bảng UC | — | **59/162 (51 227 ký tự)** | **0** |
| id có hậu tố `-p<page>` | — | 125/235 | 22 (đều là restart số thật) |

**Nguyên nhân.** `joinVisualLines` gộp số trang thành một dòng: trang in 26 →
`2 6`, trang 135 → `13 5`. `_NumberedLine` đọc `2 6` thành chương `2` với tiêu
đề `6` → `_HeadingTracker` chấp nhận là heading → `_flush()` đóng UC vừa mở ở
cuối trang trước; phần còn lại của bảng thành unit `SEC-2-p26`. Mọi UC có bảng
vắt qua ngã ba trang đều mất flow: model nhận unit UC thiếu precondition /
flow / post-condition (đúng những gì brief Cockburn ở prompt p2 đi tìm) nên trả
điểm 0, còn phần đuôi bảng lại bị chấm như "mục tài liệu".

**Fix (trong working tree).** (1) `_NumberedLine.parse` đòi tiêu đề có ít nhất
một chữ cái — dòng chỉ có số (`2 6`, `13 5`) là page furniture, không vào
heading detection, `_sectionIn` hay `runMembers`. (2) `_BodyScan._flush` không
emit unit mà toàn thân không có chữ cái: đo trên OTES, banner `USE CASE –
UC014` (bảng in `UC0114`) sau fix (1) hút đúng dòng footer thành "use case"
`5 5` 3 ký tự.

Trạng thái: **đã đo lại trên file thật** — 63/63 UC giữ nguyên flow,
`SEC-*` không còn thân UC, 0 unit không chữ cái. `flutter analyze --fatal-infos
--fatal-warnings` sạch, `flutter test` **687/687** (thêm 2 test hồi quy trong
`requirement_splitter_test.dart`), server `pytest` 99+1 skip pass.
`kParserVersion` bump 1.4.1 → **1.4.2** (snapshot cũ không tái dùng). Snapshot
1.4.1 của lượt chấm đêm 2026-09-22 đã được sao lưu nguyên trạng ra
`reviews/workspace-snapshot-2026-09-22-parser1.4.1.json` trước khi bump để còn
đối chiếu.

---

## Addendum 1.4.1 (cùng ngày, sau khi chạy trên PDF OTES thật)

Chạy parser 1.4.0 lên `D:\Download\SRS.pdf` (217 trang, bản OTES thật) cho thấy
fix 1.4.0 **chưa đủ**: vẫn 85/85 unit là use case. Nguyên nhân: Syncfusion
`extractText` trả **mỗi từ một dòng** trên toàn bộ trang thân (đo: avg 1.0
từ/dòng), nên `3.3 Availability` vỡ thành `3.3` / `Availability` hai dòng →
`_NumberedLine` không bao giờ khớp heading → không section nào được mở. Đây
đúng bẫy "token-per-line" đã ghi ở `docs/tech-lead-brief.md` (commit 5d05f3a),
nhưng 1.4.0 chỉ kiểm trên SRS tổng hợp có dòng thật nên không lộ.

**Fix (parser 1.4.1):** `PdfParser` dựng lại text trang từ
`extractTextLines` — gom các text-run theo vạch ngang (chênh `bounds.top` ≤ 3
px, trong hàng sắp theo `bounds.left`), fallback `extractText` khi trang không
có line nào. Hàm gom `PdfParser.joinVisualLines` là hàm thuần, có test riêng
trong `parse_service_test.dart`. Đo lại trên OTES thật: **235 unit** —
`useCase: 63` (đúng số bảng), `section: 162`, `functional: 5`,
`nonFunctional: 4`, `statement: 1`; NFR (p.153), conceptual dictionary,
toàn bộ SDS (architecture, class dictionary, UI fields, ERD p.181–185) đều
thành unit. Nhiễu còn lại: heading rác từ header/footer (`SEC-14-p141`),
đuôi bảng UC thành section — người dùng lọc/bỏ chọn trong inventory; nên lọc
kind trước khi chấm để không đốt quota vào section thuộc front-matter.
`kParserVersion` bump 1.4.0 → 1.4.1 (snapshot cũ không tái dùng).

> **Đọc tiếp Addendum 2 (2026-09-22):** "nhiễu header/footer" nói trên không
> phải nhiễu lọc được — nó là **thân bảng UC bị cắt** và là nguyên nhân chính
> khiến lượt chấm AI thật đầu tiên trả về điểm đồng loạt ~2.0/10. Con số 235
> unit của 1.4.1 ở trên đã bị thay bằng 130 unit sau fix.

Trạng thái: **đã vá và xác minh 2026-09-21** — `flutter analyze --fatal-infos
--fatal-warnings` sạch (đã sửa thêm 1 lint `prefer_null_aware_operators` ở
`requirement_splitter.dart`), `flutter test` **681/681 pass**. Một expectation
test phải đổi theo hành vi mới đúng thiết kế: `import_run_review_modal_test`
fixture `XX-1` (kind `useCase`, prefix lạ) nay được chọn → modal "Chấm 3 mục"
thay vì 2.
(sandbox không có Dart/Flutter toolchain; xem mục 6). File "report chính thống" mà
người dùng nhắc tới **chưa được đính kèm** — toàn bộ chẩn đoán dưới đây dựa trên đọc
code + tái hiện bằng một SRS tổng hợp viết đúng theo mẫu SRS đồ án FPT (Record of
Changes → Table of Contents → 1. Product Overview → 2. User Requirements (Actors,
Use Cases list + descriptions) → 3. Functional Requirements (Screen Flow / Screen
Descriptions / Function Descriptions) → 4. Non-Functional Requirements → 5.
Requirement Appendix (Business Rules / Application Messages / Common Requirements)).

## 1. Kết quả đo trước khi sửa (parser 1.3.0)

Chạy một bản port Python 1:1 của `TableOfContents.parse` + `RequirementSplitter` +
`unitFromRequirement` (`/tmp/probe/splitter_port.py`, không commit) trên SRS mẫu 18
trang:

| | Trước (1.3.0) | Sau (1.4.0) |
|---|---|---|
| Số unit | 12 | 24 |
| Use case | 6 (5 ID + 1 `UC-T`) | 5 (đủ, không trùng) |
| Đoạn văn của 12 mục không có ID (Overview, Actors, Screen/Function desc., 4 mục NFR, Messages, Common req.) | **0** | 12 |
| Thân use case UC-01 (Wiegers template) | cụt ở `Normal Flow:` — mất toàn bộ main/alternative/exception flow | nguyên vẹn |
| Kind của `BR-01..03` | `functional` | `businessRule` |
| Mục lục có `II. Table of Contents` | không nhận là trang TOC | nhận |

Người dùng nhìn thấy đúng hiện tượng đã mô tả: inventory chỉ có hàng Use case (và
vài BR nếu ID đứng đầu dòng), mọi thứ khác biến mất, không có thông báo gì.

## 2. Nguyên nhân gốc (theo thứ tự ảnh hưởng)

1. **Body scan chỉ tạo unit từ dòng có ID.** `_splitByBody` mở unit khi dòng khớp
   `^(NFR|FR|NF|UC|BR|SR)[-_ ]?\d+|F-\d+`, một câu `shall/must/hệ thống phải`, hoặc
   hàng `Use case name:`. Không có nhánh nào đọc theo **heading**. Trong mẫu SRS
   chính thống, chỉ use case (và đôi khi BR) mang ID; Product Overview, Actors,
   Screen/Function Descriptions, toàn bộ NFR (Usability/Reliability/Performance/
   Security viết thành đoạn văn), Application Messages đều không có ID → không bao
   giờ thành unit → mọi pass (F7/F8/F9, QualityChecks, ReferenceChecks,
   ContradictionPass, LLM review) đều không nhìn thấy, vì tất cả đều đọc từ
   `document.requirements`.
2. **`_sectionHeading` (`^\d+(\.\d+){0,3}\.?\s+\S`) coi mọi dòng bắt đầu bằng số là
   heading**, kể cả `1. User enters email and password.` → mỗi bước flow đóng unit
   đang mở. Use case bị cắt còn phần header; `section` bị ghi thành `1`/`2`;
   `TransactionCounter` (F9) không còn thấy bước nào → báo "thin" sai; LLM review
   nhận stub. Không test nào bắt vì test chỉ đếm số use case.
3. **ID nằm sau nhãn (`Use Case ID: UC-01`, `UC ID and Name: UC-01 Login`,
   `Use Case No. UC01`) không mở unit** vì regex neo đầu dòng. Hệ quả kép: unit
   trước đó nuốt luôn bảng của use case sau (UC-05 trong list nuốt cả spec UC-01).
4. **`unitFromRequirement` chỉ biết prefix UC/BR/NFR/FR/SR.** `F-01`, `NF-02` (mẫu
   VN thật, đã hỗ trợ ở parser từ 1.2.0), `ST-n`, `UC-Tn` đều rơi vào `unknown` →
   `malformed=true` → `selected=false` → **không bao giờ được review** dù đã parse
   được. Trái với AC1 của `docs/real-srs-id-support.md`.
5. **Frame "thiếu mục" của `BlueprintChecks` là báo cáo 5 phần** (Introduction/PMP/
   SRS/SDD/Impl&Test, cần ≥ 2 khớp). SRS độc lập không khớp phần nào → check tự tắt,
   thiếu chương Non-Functional cũng không ai báo. `TableOfContents._chapter` cũng
   không nhận `II. Table of Contents … 3` (số La Mã) nên trang mục lục ngắn có thể
   không được nhận là TOC.

## 3. Đã sửa gì (parser 1.3.0 → 1.4.0)

`app/lib/data/parsing/requirement_splitter.dart` — viết lại body scan thành
`_BodyScan` + `_HeadingTracker`:

- **Phân biệt heading với bước đánh số** (`_HeadingTracker`): tiêu đề > 12 từ hoặc kết
  thúc `.;,` → bước; dãy `1.` `2.` `3.` cách nhau ≤ 8 dòng, cùng kiểu dấu câu → danh
  sách (bảng Actors, Messages, flow Title Case); số nhiều cấp lùi so với heading vừa
  nhận (`1.1 Login with Google` khi đang ở `2.2.2`) → nhãn flow; trong unit đang mở,
  số nhiều cấp chỉ là heading nếu là **kế tiếp hợp lệ** (`2.2.3`/`2.3`/`3`/`2.2.2.1`
  sau `2.2.2`); `n == bước trước + 1` → bước, trừ khi 3 từ đầu có từ chương
  (`requirement|overview|yeu cau|chuc nang|…`) và không mở đầu bằng tác nhân.
- **Unit theo mục** (`SEC-<số mục>`, ví dụ `SEC-4.2.3`): đoạn văn dưới heading không
  sinh unit có ID nào, ≥ 12 từ, được gom thành một unit với `section = "4.2.3
  Performance"`, `title = "Performance"`, text nguyên văn (cắt ở 6000 ký tự). Kind
  suy từ đường dẫn heading, lá trước gốc: từ chất lượng (`performance|security|
  usability|interface|phi chuc nang|hieu nang|bao mat|…`) → `nonFunctional`;
  `business rule|quy tac` → `businessRule`; `functional|function|feature|screen|
  chuc nang|man hinh|…` → `functional`; còn lại → `section` (Overview, Actors,
  Messages). Câu `shall/must` không ID dưới heading đã phân loại nhận kind đó (được
  chọn review); dưới heading chung chung thì ở lại cùng đoạn văn; không có heading →
  `statement` như cũ. Đánh số lặp giữa các phần → `SEC-1.1`, `SEC-1.1-p57`.
- **ID có nhãn** (`_labelledId`) mở unit; nhãn trần `Use Case ID` (ID rơi xuống dòng
  sau) đóng unit trước. Heading mang ID (`2.2.2.1 UC-01 Login`) mở đúng unit đó.
- **Tách câu modal trong unit đang mở** chỉ khi unit không phải use case **và** đã
  có một câu modal — ID in một mình trên dòng giữ được câu `shall` theo sau.
- `kindForId`: `UC`→useCase, `NF*`→nonFunctional, `BR`→businessRule, còn lại
  functional. `_firstIdIn` (đường TOC) cũng nhận ID có nhãn.

Các file khác:

- `srs_document.dart`: `kParserVersion = '1.4.0'`; `RequirementKind` thêm
  `nonFunctional`, `businessRule`, `section`; `RequirementItem.title` (tuỳ chọn) và
  `hasSyntheticId`.
- `workspace_unit.dart`: `UnitKind.section('Section')`; mapping ưu tiên prefix
  (thêm `F-`, `NF-`), không có prefix thì theo `RequirementKind`; title lấy
  `item.title` nếu có. `workspace_widgets.dart`: nhãn VN `Mục tài liệu`.
  `workspace_view_model.dart`: `otherRequirementsCount` tính cả section.
- `quality_checks.dart`: `_looksNonFunctional` nhận `kind == nonFunctional`.
  `reference_checks.dart`: `duplicateIds` bỏ qua ID tổng hợp (`ST-`, `SEC-`, `UC-T`).
- `blueprint_checks.dart`: thêm frame `srsReportExpectedSections` (Product Overview /
  User Requirements / Functional / Non-Functional / Requirement Appendix, khớp trên
  tiêu đề đã fold nên nhận cả tiếng Việt); `missingSections` chọn frame khớp nhiều
  phần nhất, hoà thì giữ frame 5 phần. `table_of_contents.dart`: `_chapter` nhận
  `II.`/`III.`.

Không đổi contract server (`contracts/review.schema.json`), không đổi prompt.
`python3 tools/check_guardrails.py` pass.

## 4. Test đã thêm (chờ chạy)

- `test/requirement_splitter_test.dart`: 4 group mới (bước đánh số không cắt use
  case — kể cả Wiegers `1.0`/`1.1`/`1.0.E1`, Title Case không dấu chấm, chương tiếng
  Việt ngay sau bước 2, bảng Actors; ID có nhãn; unit theo mục — kind theo heading,
  không sinh twin khi mục đã có ID, `must` trong Overview ở lại đoạn văn, ID trùng
  giữa các phần; kind theo prefix; ID đứng một mình giữ câu shall).
- `test/workspace_models_test.dart`: `F-`/`NF-` không còn malformed; kind parser
  quyết định khi không có prefix (`ST-4` functional, `SEC-4.2.3` nonFunctional,
  `SEC-1` section).
- `test/blueprint_checks_test.dart`: SRS độc lập được chấm theo frame SRS (thiếu
  NFR → high); chương phi chức năng không thoả "Functional"; báo cáo 5 phần vẫn
  theo frame cũ. `test/blueprint_builder_test.dart`: TOC số La Mã.
- `test/workspace_messages_vi_test.dart`: nhãn `Section`.

Mọi expectation của test cũ (18 case splitter + fixture `buildValidPdf`/`Docx`/
`DuplicateId`/`ProseOnly` của `srs_pipeline_qa_test`) và test mới đều đã được chạy
lại trên bản mirror Python của thuật toán mới và giữ nguyên kết quả — nhưng đó là
mirror, không phải Dart.

## 5. Rủi ro / giới hạn còn lại

- Heading tiếng Việt viết thường 4+ từ không có từ chương (`1. Phạm vi dự án`) đứng
  ngay sau một dãy bước **trong unit đang mở** vẫn có thể bị đọc thành bước.
- Bước Title Case 1 từ hoặc flow chỉ có một bước (`1. Logout`) vẫn có thể bị đọc
  thành heading (hành vi cũ, không tệ hơn).
- Unit `section` gửi cho LLM với prompt ISO 29148 hiện tại — prompt chưa biết đó là
  "một mục tài liệu" chứ không phải một requirement; ~~nên thêm hint theo `kind` ở
  `server/app/prompt.py` sau khi có kết quả thật~~ **ĐÃ LÀM (2026-09-21, prompt
  p2):** `_unit_brief(requirement_id, section)` chọn briefing chuyên biệt — bảng UC
  (Cockburn: actor/pre/post Success+Fail/main flow 3–7 bước/exception khớp
  `[Exception N]`/cite BR), mục NFR (định lượng: số + đơn vị + điều kiện đo, theo
  quality-rules §B), mục SDS (dictionary đủ thuộc tính/kiểu/visibility, tên nhất
  quán, design nói HOW không lặp WHAT — viewpoints.md), BR, section văn xuôi.
  Không đổi contract; an toàn cache vì brief suy ra từ `requirement_id`+`section`
  (đã nằm trong cache key) và `prompt_version` bump p1→p2. Test:
  `server/tests/test_prompt.py` (8 case).
- Unit theo mục được chọn review mặc định → SRS lớn dễ chạm trần 40 unit/lượt; người
  dùng bỏ chọn được trong inventory (lọc `Mục tài liệu`).
- Frame SRS chỉ chấm khi ≥ 2 phần khớp, vẫn có thể im lặng với mục lục đặt tên rất
  khác chuẩn.

## 6. Cần người dùng làm

1. Đính kèm file report chính thống (PDF) để chạy lại đúng trên tài liệu thật; nếu
   là DOCX cũng gửi — DOCX đi đường body scan hoàn toàn.
2. `cd app && flutter analyze && flutter test` — code mới chưa được compile ở đây.
   Nếu analyzer báo lỗi ở `requirement_splitter.dart`, `workspace_unit.dart`,
   `blueprint_checks.dart`, gửi log lại.
3. Nhập lại tài liệu (parser version đổi → snapshot cũ không tái dùng) và so số
   liệu inventory với bảng ở mục 1.
