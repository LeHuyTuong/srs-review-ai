# Adapter — port map vào app `srs-review-ai`

Không phải kế hoạch code. Đây là **bản ánh xạ**: mỗi luật trong `review-rules/` → đã có trong app ở đâu / còn thiếu gì / port ở tầng nào (Dart deterministic, server prompt, server DiagramType). Bổ sung cho `docs/evidence/rubric-vs-skills-map.md` (giữ nguyên file đó làm lịch sử; file này là trạng thái mong muốn).

Ký hiệu: ✅ có · 🟡 một phần · ❌ chưa · ➖ ngoài scope app.

## 1. Luật SRS → app

| Luật (file §) | App | Tầng | Ghi chú port |
|---|---|---|---|
| quality-rules §A.2 Unambiguous | ✅ `ambiguousWording` | Dart `quality_checks.dart` | phrase list §C là superset — so và thêm phrase **có ví dụ thật** |
| §A.3 Testable | ✅ `ambiguousWording`+`missingPostcondition` | Dart | |
| §A.4 Complete | ✅ `placeholderTbd`, `missingActor` | Dart | |
| §A.5 Consistent | ✅ `duplicateIds`, `crossArtifactName`, contradiction pass | Dart | |
| §A.6 Traceable — format ID `FR-<EPIC>-NN`/`UC-NNN`/`NFR-<CAT>-NN` | ❌ **CHẶN BỞI PARSER** | Dart — nhưng chưa làm được | `requirement_splitter._canonicalId` viết lại mọi ID thành `PREFIX-NN` **trước khi** check nhìn thấy → check sẽ chấm chính cái chuẩn hoá của mình, không phải tài liệu. Phải để splitter giữ **ID gốc** bên cạnh ID chuẩn hoá trước |
| §A.7 Prioritized | ✅ `missingPriority` | Dart | |
| §A.8–10 | ➖ LLM | server `prompt.py` | checklist 6 điểm hiện chỉ có "feasible", chưa có "necessary"; cần thêm + ép output dạng câu hỏi (info) |
| §B NFR định lượng + CAT ISO 25010 | 🟡 LLM chấm "testable" | Dart — `CheckId.nfrUnquantified` mới | deterministic: dòng có ID `NFR-` mà không có số (`\d`) hoặc không có đơn vị/điều kiện → red |
| §D UC 3–7 transaction | ✅ `ucSize` | Dart | |
| UC count ≥ 20 | 🟡 `ucCount` | Dart | app còn trần 25; v0.2 bỏ trần — cần sửa `rubric.json` + bump version |
| Post Success **và** Fail riêng | 🟡 `missingPostcondition` chỉ check có/không | Dart | tách thành `missingPostFail` amber |
| `[Exception N]` inline ↔ mục E<N> | ❌ | Dart — `CheckId.exceptionMarkMismatch` | đếm mark vs heading |
| RTM FR↔UC 0 orphan | ❌ | Dart — `CheckId.rtmOrphan` | cần parser bảng RTM (F.2); có thể suy từ "Related FR" trong bảng UC |
| Khung A–F | ❌ | Dart — `CheckId.missingSection` | so heading với `srs-outline.md`; red |
| Ambiguity scan re-run trước đóng | ✅ (chạy mọi lần) | | |

## 2. Luật SDS → app

App hiện **chấm SRS**; SDS mới có vision chain (steps 5–7). Port SDS text-rules là milestone riêng.

| Luật | App | Tầng | Ghi chú |
|---|---|---|---|
| viewpoints §1 — 7 mục | ❌ | Dart `missingSection` (dùng chung với SRS, outline khác) | |
| Hard rule 4 WHAT-only | ❌ | server prompt (cần hiểu nghĩa) | prompt: "đoạn này trả lời câu nào trong 4 câu HOW?" |
| Hard rule 5 technology→ADR | ❌ | Dart — `CheckId.techWithoutAdr` | danh sách tên công nghệ (regex + từ điển) vs heading `ADR-` / `docs/adr/` |
| templates/adr — ≥ 2 option | ❌ | Dart | đếm hàng bảng Options |
| RTM FR↔element | ❌ | Dart `rtmOrphan` (chung) | app hiện null vĩnh viễn cột test → giữ; FR↔element làm được nếu parse bảng §7.1 |
| **7 chain** cross-artifact (scoring §5) | 🟡 1/7 `crossArtifactName` | Dart + vision | chain 2 (FK matrix) đã có probe r20; **chain 3 thuần text — port bước 2**; chain 4–7 cần element list từ vision `DiagramDescribe.elements/relations` → so tên. Chain 7 (seq ↔ kiến trúc khai báo) cần thêm bộ nhận diện style theo `architecture-patterns.md` §4 |
| Thang 5+2+2+1 | 🟡 `document_verdict.dart` — cùng hình dạng, **còn lệch 2 chỗ** (`scoring.md` §9): sàn 7 bucket all-or-nothing, trừ theo row không theo finding. ~~prefix `FLOW-`~~ **đã sửa 2026-09-15** → `deductingFamilies = ERD- / SM- / SEQ-CLS-` | Dart | sàn về **5 tiêu chí tỉ lệ** (`scoring.md` §3); traceability tính thật khi có `rtmOrphan`. **Không thêm `ACT-`**: `DiagramKind.activity.family` là `DOC`, không phải `ACT` — thêm vào là dựng lại đúng lỗi `FLOW-` (một luật không bao giờ chạy được) và test mới sẽ bắt |
| Severity | 🟡 app `high/medium/low`, `placeholderTbd` = medium | Dart `review_models.dart`, `quality_checks.dart` | map high→red, medium→amber, low→info; nâng `placeholderTbd` lên high (hard rule) |

## 3. Chính sách UML 2.5 → `server/app/diagram.py`

| Loại UML | `DiagramType` server | Family ledger | Câu hỏi judge | Cần làm |
|---|---|---|---|---|
| Class | `class` | SEQ-CLS | ✅ | thêm câu về multiplicity hai đầu, agg/comp |
| Object | — | SEQ-CLS | ❌ | đi `unknown`; đủ (hiếm) |
| Package | `component` (gộp) | PKG | 🟡 | thêm câu "vòng phụ thuộc" |
| Composite structure | — | PKG | ❌ | `unknown`; đủ |
| Component | `component` | PKG | ✅ | thêm provided/required interface |
| **Deployment** | `component` (gộp) | **DEP mới** | ❌ | **thêm `DEPLOYMENT` + family `DEP`**: node stereotype, artifact, protocol, ↔ C4 L2 |
| Profile | — | DOC | ❌ | `unknown`; đủ |
| Use Case | `use_case` | UC | ✅ | thêm "System/Database as actor" |
| **Activity** | `unknown` | **ACT mới** | ❌ | **thêm `ACTIVITY` + family `ACT`**: initial/final, guard đủ+loại trừ, fork/join, swimlane, **flowchart detector** (G6a) |
| State machine | `state_machine` | SM | ✅ | |
| Sequence | `sequence` | SEQ-CLS | ✅ | thêm sync/async/reply arrow check |
| Communication | — | SEQ-CLS | ❌ | classifier keyword "communication diagram" → `sequence` + câu hỏi numbering |
| Timing | — | SEQ-CLS | ❌ | `unknown`; đủ |
| Interaction overview | — | ACT | ❌ | classifier → `ACTIVITY` |
| C4 L1/L2/L3 (E1) | `component` | PKG | 🟡 | thêm câu: technology mỗi box, ↔ Deployment |
| ERD (E2) | `erd` | ERD | ✅ | thêm "caption ghi notation" |
| G1–G8a chung (G8b cần mắt người, không tính điểm) | ❌ | Dart `diagram_type_classifier.dart` + server | G1 caption không tên loại → `CheckId.diagramCaption` Dart; G2 3–5 dòng → Dart đếm dòng dưới caption; G6 non-UML → server judge `unknown` trả `non_uml=true` **kèm ba cờ `has_named_containers` / `has_protocol_on_edges` / `externals_separated`**: đủ ba → G6b amber, thiếu bất kỳ → G6a red |

Thay đổi enum server = Pydantic StrEnum → client `DiagramKind.wire` phải có giá trị tương ứng, test 'every kind sends a wire and family the server accepts' sẽ bắt (xem comment trong `diagram_type_classifier.dart`). Thêm `ACT`/`DEP` vào whitelist family của judge schema.

## 4. Thứ tự port đề xuất (mỗi bước = 1 PR, test đi kèm)

Thứ tự này đổi ở **v0.2** sau lần chạy thật trên OTES: chain 3 nhảy từ bước 5 lên bước 2, vì nó là check bắt lỗi nặng nhất mà lại **không cần vision** — chỉ so tên lifeline/message với danh sách class/operation đã có sẵn dưới dạng text.

1. **`nfrUnquantified` ĐÃ PORT + TEST XANH 2026-09-15** (`quality_checks.dart` + `CheckId` + wire/label + hai switch UI + `contracts/review.schema.json` + 7 test mới + 1 test chống lệch schema↔enum). `pytest` 90 passed · `quality_checks_test.dart` 20 passed. Chạy thật trên pipeline: TC-01 in ra `NFR-01 names a measurement condition but no figure to measure against` — luật red đầu tiên của rulebook mà app bắt được.
   - **Không nối vào sàn** (`floorCriteria` vẫn 7 bucket): hard rule 6 do thành phần NFR +2 đo, không phải sàn (luật một-chỗ `scoring.md` §1b).
   - **`idFormat` KHÔNG port — chặn bởi parser**, xem bảng §2. Đã viết code rồi gỡ bỏ sau khi kiểm chứng: với tài liệu thật nó fail 100% FR và NFR (splitter đã chuẩn hoá `UC01`→`UC-01`), tức là một check sai mọi lúc. Ship nó tệ hơn không ship.
   - **`missingSection` chưa làm**: cần model outline (danh sách mục A–F) mà `SrsDocument` chưa có. Cũng là việc parser.
   - *Còn lại trong bước 1: sửa bug prefix `FLOW-` trong `document_verdict.dart`* (scoring.md §9) — hiện SM/SEQ-CLS red không bao giờ bị trừ.

   **Bài học**: hai trong ba check "thuần text, dễ" của plan 7 thực ra chặn ở tầng parser. Plan 7 §7 ước lượng sai vì nó nhìn luật, không nhìn dữ liệu mà luật sẽ chạy trên. Check tiếp theo: xem parser cấp gì trước khi xếp độ khó.
2. **Chain 3 (sequence ↔ class)** — `CheckId.seqClassOrphan`. Không cần vision: lifeline và message name lấy từ text quanh hình + `DiagramDescribe.elements/relations` nếu đã có; danh sách class/operation lấy từ bảng §4.2. So tên, xuất hai tỉ lệ. **Bằng chứng ưu tiên: trên OTES ra 0/40 message và 6/26 lifeline — phát hiện nặng nhất của cả lần chạy.**
3. **Thang điểm liên tục** (`scoring.md` §2–§6) — sửa `document_verdict.dart`: sàn 7 bucket all-or-nothing → 5 tiêu chí tỉ lệ; bỏ trừ theo row, thay bằng phạt hard-rule tối đa −2.
4. `DEPLOYMENT` + `ACTIVITY` DiagramType + family `DEP`/`ACT` + flowchart detector + **G8** (trùng số hiệu / hình dùng lại — thuần text, so caption).
5. `techWithoutAdr` + `missingSection` (SDS outline) + **luật N/A hàng loạt** (`quality-rules.md` §E — đếm theo trường, thuần text).
6. `rtmOrphan` (parse bảng RTM) → bật cột traceability trong `document_verdict.dart`.
7. Chain 2, 4, 5, 6 cross-artifact từ `DiagramDescribe` — cần vision quota, làm sau.

Hard rule 9 (PII) và 10 (ảnh bên thứ ba) **không port vào app** ở giai đoạn này: cần vision đọc nội dung ảnh và nhận diện thương hiệu, sai số cao. Giữ ở tầng reviewer người/Claude.

Mọi bước: bump `rubric.json.version` nếu đổi weights/threshold (cache key). Bước 1 phải bump vì gate `uc_count` bỏ trần 25 (scoring.md §8).

## 5. Việc phát sinh từ 7 quyết định đã ký (RULEBOOK §9, 2026-09-15) — một PR, chạy test trước khi merge

> **Trạng thái 2026-09-15: ĐÃ SỬA CẢ A VÀ B, NHƯNG CHƯA CHẠY TEST.** Shell sandbox hỏng cả session. Toàn bộ thay đổi ghi ở `docs/adr/0009-rubric-v3-weights-and-uc-ceiling.md`. Việc còn lại của người có shell: chạy `server/.venv/bin/python -m pytest` và `flutter test`, sửa mọi chỗ đỏ. Ba test pin bên dưới là **tripwire cố ý** — chúng phải đỏ trên bản cũ và xanh trên bản mới.

Hai quyết định chạm số trong app. Danh sách file đầy đủ:

**Việc A — Q1: bỏ trần 25 use case**

| File | Đổi gì |
|---|---|
| `server/app/rubric.json` | `deterministic_checks.uc_count`: bỏ khoá `max`, hoặc giữ `max` nhưng đổi ngữ nghĩa thành `"max": null` — **chọn cách 2** để `rubric_config.dart` không crash khi cast; ghi `"gate": "Defense requires >=20 completed use cases; no upper bound (rulebook 1.0 Q1). UC size 3-7 is a separate scored criterion."` |
| `app/lib/data/checks/rubric_config.dart` | `ucCountMax` → `int?`; `fromJson` đọc `ucCount['max'] as int?`; fallback `ucCountMax: null` |
| `app/lib/data/checks/syllabus_checks.dart` | check `ucCount`: chỉ fail khi `< min`; `> max` không còn là finding (hoặc info nếu muốn giữ tín hiệu) |
| `app/test/syllabus_checks_test.dart` | test `'passes inside the recommended 20-25 range'` → đổi tên + case: 63 UC phải **pass** |
| `server/tests/test_contract.py` | dòng assert `uc_count.min == 20` giữ; thêm assert `max is None` |

**Việc B — Q6: weights `.25 / .40 / .20 / .15`**

| File | Đổi gì |
|---|---|
| `server/app/rubric.json` | `version: "v2"` → **`"v3"`**; `quality_criteria`: clear .25, testable .40, complete .20, consistent .15; `provenance` giữ chữ "starting proposal", thêm "Reweighted 2026-09-15 per rulebook 1.0 Q6: testable raised because it was the dominant failure on OTES." |
| `server/tests/test_rubric_pins.py` | `assert rubric["version"] == "v3"`; dict weights mới. **Đây là tripwire cố ý** — test này phải đỏ trước khi sửa, xanh sau khi sửa |
| `server/tests/test_api.py` | `assert body["rubric_version"] == "v3"` |
| `app/lib/data/checks/rubric_config.dart` | fallback `version: 'v3-local'` |
| `server/app/prompt.py` | nếu prompt có nêu weights hoặc thứ tự ưu tiên tiêu chí → cập nhật cho khớp (kiểm tra bằng grep `0.3` / `testable`) |

Sau A + B: `server/.venv/bin/python -m pytest` và `flutter test` phải xanh; **verdict cache cũ tự vô hiệu** vì key băm version. Ghi vào `docs/adr/0009-rulebook-1.5-weights.md` theo `templates/adr.md` (0008 đã dùng cho đánh giá KiraAI) — chính rulebook đòi mọi thay đổi có ADR, app phải làm gương.
