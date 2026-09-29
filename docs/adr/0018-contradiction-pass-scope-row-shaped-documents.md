# ADR-0018 — `crossArtifactName` (chain 1) is scoped to row-shaped documents; a prose SRS returning 0 is the designed outcome, not a failure

**Status:** Accepted
**Date:** 2026-09-29
**Deciders:** Amy
**Related:** `app/lib/deterministic_checks/checks/contradiction_pass.dart`, `app/lib/diagram_audit/services/cross_artifact_checker.dart` (`stemOf`), `review-rules/references/scoring.md` §5 (chain 1), `review-rules/adapters/app-port-map.md` (hàng chain 1), `docs/evidence/r13_otes_deterministic_ceiling.md`, `docs/evidence/chain1-otes-2026-09-28.md`, `docs/evidence/vision-reality-2026-09-26.md`, `app/test/chain1_otes_real_document_test.dart`

## Context

Chain 1 là check "naming drift" — cùng một khái niệm bị gọi hai tên. Trên HisWise
SDS, tám finding đắt nhất của lượt chấm đều cùng hình dạng này, nên
`ContradictionPass` được viết (round 11) để tái tạo tín hiệu đó bằng thuần text:
với mỗi unit của `SrsDocument`, lấy **cụm từ viết hoa đầu tiên** của unit text làm
"tên thực thể", chuẩn hoá bằng `stemOf` (lowercase + bỏ đuôi `s`), và bắn finding
khi một stem có **≥ 2 original khác nhau** ở **≥ 2 section khác nhau**.

Ba thực tế cùng tồn tại nhưng chưa bao giờ được đặt cạnh nhau:

1. **Trên HisWise (SDS có data dictionary + class diagram), check bắn 8** — đúng
   như thiết kế (`vision-reality-2026-09-26.md`; hàng chain 1 trong app-port-map).
2. **Trên OTES (SRS văn xuôi), check trả 0 hai lần vì hai lý do khác nhau.** Lượt
   2026-09-13 (r13) là regex thuần ASCII không match tiếng Việt — một "honest
   zero" thật ra là mù, đã vá bằng regex song ngữ 2026-09-26. Lượt 2026-09-28
   (WP6, parser 1.4.4) là *sau* khi vá: 91/91 unit đều trích được entity, 28
   stem, mà vẫn 0.
3. **Lý do của số 0 thứ hai là hình dạng tài liệu, không phải code.** Unit của
   OTES không phải dòng dictionary: 63/91 unit là bảng UC bắt đầu bằng
   bullet/động từ ("● Manage a semester."), các section văn xuôi bắt đầu bằng đại
   từ/trạng từ ("We propose…", "Currently, Online teaching…"). Cụm viết hoa đầu
   tiên của một đoạn văn là **chủ ngữ của câu**, không phải tên thực thể được
   khai báo. Detector one-phrase-per-unit chỉ có nghĩa khi **mỗi unit là một dòng
   mang tên thực thể** — đúng hình dạng SDS, không phải SRS văn xuôi.

Header của chính `contradiction_pass.dart` đã ghi "operates on the *text* of the
requirement titles" — phạm vi đó có từ round 11 nhưng chỉ nằm trong comment code.
Một số 0 im lặng trong UI không nói được mình là "0 vì đã kiểm, sạch" hay "0 vì
check không có gì để bám"; ADR này là nơi câu trả lời sống.

## Số đo (2026-09-29 — probe bơm vào đúng thuật toán của `detect`, xoá sau khi đo)

Pipeline đúng của app trên OTES thật (fitz 217 trang, parser 1.4.4, **91 unit**:
63 useCase · 27 section · 1 nonFunctional):

| Đại lượng | Giá trị |
|---|---|
| Unit trích được entity (như-shipped, 1 cụm/unit) | **91/91** — 28 stem |
| Cluster ≥ 2 section | **1** — stem `we`: original duy nhất `We`, 2 section → bị cổng ≥2-original chặn **đúng** |
| Cluster ≥ 2 original | **0** |
| Cluster qua cả hai cổng | **0** |
| Mẫu trích (unit → cụm đầu tiên) | "● Project Name: Online teaching…" → `Project Name` · "We propose…" → `We` · "Currently, Online teaching…" → `Currently` · "● Manage a semester." → `Manage` · section dài nhất (SEC-1-p14, 6 000 ký tự) → `Name` |

Nghĩa là **không cổng nào kẹt, không extractor nào thất bại**: từng cụm được
trích đúng như thiết kế, và từng cụm như thế bị cổng ≥2-original chặn đúng. Số 0 không phải check chết — nó là **không có cụm nào đạt điều kiện bắn**,
vì cụm được trích không phải tên thực thể.

Đối chứng — nếu nới extractor lấy **mọi** cụm viết hoa (3 971 cụm, 624 stem):
**10 cluster** qua cả hai cổng, đầu bảng là `lecturer` (2 original, 12 section)
và `student` (2 original, 13 section), và **cả 10 cluster đều là cặp
{Singular, Plural}**. Tức là tín hiệu drift mà check muốn có **thật** trong văn
OTES, nhưng để nhìn thấy nó phải đổi cả detector — và thứ nhận về là 10 finding
high-severity yêu cầu vision, phát ra từ danh từ thông dụng trong câu văn
("students can register"), không phải từ khai báo thực thể.

## Options considered

| Option | Pros | Cons | Chọn |
|---|---|---|---|
| **A. Giữ nguyên check; phạm vi được ghi thành ADR** | 0 thêm nhiễu; số 0 đã được chứng minh đúng cơ chế trên cả hai hình dạng (8 trên HisWise, 0 trên OTES); chi phí = 0 | Số 0 vẫn im lặng *trong UI*; người chỉ đọc dashboard không thấy phạm vi | ✅ |
| **B. Bắn finding "không áp dụng" khi 0 cluster** | kết thúc tiếng lặng bằng một dòng hiện hình | cần một classifier nhận diện "tài liệu văn xuôi" — sai một chiều là **giấu finding thật** trên SDS (tệ hơn số 0 im lặng); phá hợp đồng ghi trong `detect()`: "zero contradictions vẫn trả list rỗng, dashboard renders nothing"; finding "tôi không thấy gì" với người đọc không khác nhiễu; AC-10.6 giữ chain 1 khỏi verdict nên nó không đổi điểm | |
| **C. Nới extractor lấy mọi cụm viết hoa** | tìm được drift thật Student/Students (10 cluster) | 3 971 cụm/tài liệu → 624 stem; cả 10 cluster là số ít/số nhiều của danh từ chung trong câu văn — nhiễu ngữ pháp, không phải khai báo thực thể; 10 finding high + requiresVisionEvidence đổi cái người đọc thấy, **không** đổi verdict (plan 10 §4 cấm nâng finding lên thang điểm khi chưa có gold set) | |
| **D. Shape-detect trước khi chạy, in "N/A" thay vì "0"** | UI trung thực hơn ở cấp family | cùng cái bẫy của B ở cấp to hơn; "N/A" vs "0" là một quyết định hiển thị riêng, đáng ADR riêng, chưa có người quyết | |

## Decision

1. **`ContradictionPass` giữ nguyên như đã ship.** Phạm vi của nó là và chỉ là
   **tài liệu mà unit là dòng mang tên thực thể** (data dictionary SDS, bảng
   entity, unit có tiêu đề danh từ) — phạm vi mà header round 11 đã nêu bằng
   lời. Trên tài liệu SRS văn xuôi (hình dạng OTES: bảng UC mở bằng động từ,
   section là đoạn văn), **số 0 là kết quả được thiết kế**, với bằng chứng cơ chế
   ghi ở mục Số đo.
2. **Chuỗi honest-zero là tài liệu, không phải runtime:** ADR này +
   `chain1-otes-2026-09-28.md` + hàng chain 1 trong
   `review-rules/adapters/app-port-map.md` là nơi người đọc phải đáp xuống; test
   hồi quy `chain1_otes_real_document_test.dart` giữ số đo tái lập được.
3. **Mọi lần nới phạm vi sau này (option C) cần đủ ba thứ:** gold set trước (cấm
   của plan 10 §4), một câu trả lời cho verdict (AC-10.6 giữ chain 1 khỏi
   verdict — nới mà không có chấm điểm chỉ thêm nhiễu), và một ADR mới supersede
   ADR này.
4. **Không thêm trạng thái "N/A" lúc này** (option B/D); mở lại khi có quyết định
   hiển thị "0 vs N/A" — và khi đó phải kèm thiết kế chống sai một chiều của
   classifier (N/A sai trên SDS là giấu finding thật).

## Consequences

- **Good:** không thêm nhiễu; số 0 giữ là 0 vì đúng lý, và lý do đó giờ nằm ở
  nơi tồn tại lâu hơn comment code.
- **Cost, nhận thẳng:** với người chỉ nhìn dashboard, số 0 trên tài liệu văn
  xuôi vẫn trông giống "đã kiểm, sạch" — ADR không sửa được màn hình, chỉ sửa
  được việc không ai biết vì sao.
- **Lời mời để lại:** phép đo đối chứng cho thấy tín hiệu `Student`/`Students`
  xuyên 13 section **có thật** trong văn OTES. Không đụng tới nó cho tới khi có
  gold set (WP7 đang chờ hai người ký) — đó là điều kiện, không phải ý kiến.

## Verification

- Các số trong ADR tái lập được: `cd app && flutter test
  test/chain1_otes_real_document_test.dart` (skip có in lời giải thích nếu mất
  fixture `%TEMP%\otes_pages.json`; lệnh tái trích nằm trong
  `chain1-otes-2026-09-28.md`).
- Chiều ngược: cùng check bắn 8 trên HisWise (SDS) — số đo nằm ở
  `vision-reality-2026-09-26.md` và hàng chain 1 của app-port-map.
- Không đổi dòng code nào vì ADR này: app suite giữ nguyên xanh, guardrails 8/8,
  `git status` sạch.
- Probe tạm dùng để đo (`app/test/tmp_chain1_shape_probe_test.dart`) đã bị **xoá
  sau khi đo** — các số của nó sống trong file này; giữ lại một bản sao của
  thuật toán shipped là tạo thêm một parser thứ hai, đúng cái bẫy repo đã ghi.
