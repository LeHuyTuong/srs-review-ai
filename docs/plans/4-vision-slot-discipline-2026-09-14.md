# Plan — vision slot discipline (fix A) + family honesty (fix B)

Stack: Flutter (app/) + FastAPI (server/). Nhánh kickoff-web: Flutter →
bỏ ui-styling; vòng [7] observe bằng mắt KHÔNG chạy được (không có device
nối, model vision không đọc ảnh trong phiên harness — ghi rõ, không giả vờ).
[1] domain-brief thay bằng kho evidence có thật trong repo
(docs/evidence/vision-batch-2026-09-14.md là bằng chứng gốc của plan này).

## Understanding
Live batch 2026-09-14 (10 trang OTES, 10/10 audit) đo được: 4/10 slot
hệ thống cấp cho trang KHÔNG có diagram vẽ trên đó (0 element, 0
relation), và khi model vẫn tìm thấy lỗi (trùng tên bảng, thiếu tiền tố
'<Fields>'), findings bị phân về family của loại SƠ ĐỒ đã yêu cầu
(ERD-/SEQ-CLS-/PKG-) thay vì DOC — ledger nói sai loại artifact có lỗi.

## Existing Code
- `vision_review_service.dart` — `candidates()` (luật chọn: visual ∪
  named-type), `_row()` (subject family từ kind được phân loại).
- `diagram_type_classifier.dart` — bảng keyword tier1/tier2 trên text fold.
- `server/app/diagram.py` — `DiagramVerdict.bind_family(ID_FAMILY_BY_TYPE[...])`,
  gọi tại `main.py` sau judge.
- Test pins: `test/vision_review_service_test.dart`, `server/tests/test_diagram*.py`.

## Requirements
- Functional:
  - F-A1: trang dạng DANH MỤC (caption list dày đặc: ≥4 dòng "Figure N."
    / "Bảng N." / "Bang N." trên trang, text trang chiếm chủ yếu bởi
    caption) không được vào candidates theo diện named-type. Diện
    visual (có ảnh nhúng) vẫn vào — ảnh thật thì phải xem.
  - F-A2: khi mô tả trả về inventory RỖNG (0 element VÀ 0 relation),
    findings phải thuộc family DOC ở CẢ HAI PHÍA: server bind_family
    và client subject — ledger key hai bên khớp nhau.
  - F-A3: dòng ledger của trang inventory-rỗng có message nói thẳng
    "no drawn diagram found on this page" — không ngầm để pass-row trông
    như diagram sạch.
- Non-functional: stable-ID contract giữ nguyên (subject = family-ordinal
  theo trang); quota: không đổi cap; rerun trên OTES chỉ tốn unit cho trang
  MỚI được chọn (cache hit cho trang trùng ảnh+context).

## Assumptions
- Ngưỡng 4 caption-line là hợp lý với tài liệu chuẩn FPT/IEEE (danh mục
  hình vẽ luôn ≥10 mục; trang nội dung thường ≤2 caption). Đo lại trên
  OTES ở bước verify; nếu trượt thì chỉnh bằng số, không đổi cấu trúc.

## Plan
1. `DiagramTypeClassifier.isCaptionIndex(text)` — pure, đếm caption
   openings sau fold; dùng trong `candidates()` chặn diện named-type.
2. Server: bind DOC khi describe rỗng (1 nhánh trong endpoint + test).
3. Client: `_row()` mirror đúng luật đó (family = kind khi có inventory,
   DOC khi không) + message nói rõ; test replay bằng chứng batch (p7).
4. Re-run probe candidates trên OTES: page 9 phải biến mất, các trang
   diagram thật bị skip trước đó phải thế chỗ; ghi số vào evidence doc.

## Files / Modules Affected
app: diagram_type_classifier.dart, vision_review_service.dart, 2 test files
server: app/main.py (bind call), tests
docs: evidence/vision-batch-2026-09-14.md (append correction)

## Risks
- Chặn nhầm trang vừa có caption vừa có diagram nhỏ → vẫn vào qua cửa
  visual (imagePageIndexes) — gate chỉ siết cửa NAMED.
- Đổi subject-family trên dữ liệu đã audit = ledger key đổi (ERD→DOC);
  chưa có session thật nào chứa các dòng đó (batch là script), nên
  không cần migration.

## Acceptance Criteria (đo được)
- AC1: unit test — text danh mục 6 dòng "Figure 28. …" → `isCaptionIndex`
  true; trang có 2 caption + văn xuôi → false.
- AC2: `candidates()` trên doc dựng sẵn mô phỏng trang 9 OTES → page đó
  không có trong kết quả khi không mang ảnh nhúng.
- AC3: pytest — verdict với elements=[] relations=[] → mọi finding.family
  == 'DOC' bất kể diagram_type yêu cầu; inventory khác rỗng giữ family
  theo type.
- AC4: dart test mirror AC3 ở client: subject dòng p7-style = 'DOC-xx',
  message chứa 'no drawn diagram found'.
- AC5: probe lại trên OTES thật: page index 9 không còn là candidate;
  số candidates tụt ≥1; in bảng so sánh trước/sau vào evidence doc.
- AC6: toàn bộ app tests + server tests xanh; analyze/ruff-clean.
