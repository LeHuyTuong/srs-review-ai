# Plan 10 — Đóng các gate còn mở, và những chỗ chính plan 9 để lại (2026-09-26)

**Kế thừa:** plan 9 dựng được hạt nhân consistency (P0a/P0b/P1, chain 2, chain 3,
P2 submission, ADR 0015). Trạng thái: app **938 test xanh**, server **228 pass**,
`dart analyze lib test` sạch, guardrail **8/8**.

Plan này **không** dựng thêm tính năng mới. Nó đóng những lỗ hổng mà chính
plan 9 để lại, và làm ba việc mà `docs/roadmap.md` đã ghi **MỞ** từ 2026-09-24.

> **Đọc trước khi làm:** `docs/evidence/vision-reality-2026-09-26.md` (P0a) và
> `docs/plans/9-consistency-first-2026-09-26.md` §9 (AC). Không cần đọc lại toàn bộ.

---

## 0. Kiểm kê việc còn lại, đo trước khi lập kế hoạch

Bốn mục, xếp theo **rủi ro sai sót** chứ không theo độ dễ:

| # | Việc | Bằng chứng nó còn thật |
|---|---|---|
| **A** | **Chain 3 chưa có test ở tầng service** | `test/vision_review_service_test.dart` grep `chain` → chỉ khớp 6 dòng, tất cả là `DiagramKind.sequence` trong bài toán *ứng viên*, không dòng nào assert ra một `chain3-sequence` row. Code chạy ở `vision_review_service.dart:516`. |
| **B** | **AC4 chưa đo lại trên OTES thật** | P1 chứng minh *cơ chế* qua 5 test với dữ liệu tự dựng. Chưa có lần chạy nào đưa text OTES thật vào `ContradictionPass`. |
| **C** | **3 gate roadmap vẫn MỞ** | `docs/roadmap.md:14,16,17`: M2 gold set · M4 precision/recall ảnh · M5 ba gate nghiệm thu. |
| **D** | **P3 màn hình giáo viên + P4 CRUD** | Đã chốt **không làm** ở plan 9; seam `core/role/app_role.dart` đã có. |

**Vì sao A đứng đầu.** A là hỗng hống do chính tôi tạo ra 20 phút trước: nối
chain 3 vào service mà không có một test nào chạm tới nhánh đó. 11 unit test của
`cross_artifact_chain3_test.dart` kiểm hàm thuần, **không kiểm** việc service có
gom đúng `sequenceLifelines` từ trang SEQ-CLS hay không. Đó chính là chỗ dễ
sai nhất: gom nhầm thì chain 3 luôn ra 1.0 và **tự khen mình đúng**.

---

## 1. Phase A — Test tầng service cho chain 3 (LÀM ĐẦU TIÊN)

**Bài toán:** chứng minh `VisionReviewService.audit()` gom dữ liệu chain 3
**đúng loại hình** và **không tự so với chính nó**.

Bốn ca, mỗi ca một lỗi có thể xảy ra:

| # | Ca | Kỳ vọng |
|---|---|---|
| A1 | Một audit trả về lifelines + messages | Có đúng một row `chain3-sequence`, `actual` khớp tỉ lệ |
| A2 | **Chỉ** audit trang class, không có sequence nào | **Không** có row chain 3 (thiếu một nửa = không đo) |
| A3 | Trang sequence `unreadable` khác 0 | `chain3-sequence` **không** sinh, không phải ra 0 |
| A4 | Trang ERD có entity | Entity **không** được đưa vào `auditedClassNames` (ERD không phải class) |

A4 là ca quan trọng nhất: hiện tại nhánh `else if (tentativeLabel == 'DOC' || ==
'ERD')` là **nhánh rỗng** — nghĩa là không có gì kiểm được. Test phải chứng minh
entity ERD không lọt vào phía class, vì nếu lọt thì chain 3 so lifeline với chính
entity của ERD và luôn khớp.

**AC-A:** 4 ca xanh; `dart analyze lib test` sạch; **không** sửa code `lib/` trừ
khi test lộ ra lỗi thật (khi đó ghi lại lỗi trong commit message, không sửa lặng).

---

## 2. Phase B — Đo lại chain 1 trên OTES thật (đóng AC4)

**Bài toán:** AC4 của plan 9 nói *"số finding chain 1 trên OTES > 0"*. Điều đó
**chưa được kiểm chứng** — mọi gì có hiện nay là test với dữ liệu tự dựng.

- Dùng đúng tài liệu đã có: `server/5935d26a…-OTES…pdf.docmap.json` sidecar và
  `app` đã parse được OTES thật (kết quả 130 unit, 63/63 UC theo
  `docs/review-parser-coverage-2026-09-21.md`).
- Chạy `ContradictionPass.detect()` trên **SrsDocument thật của OTES**.
- Ghi vào `docs/evidence/chain1-otes-2026-09-26.md`: số finding trước/sau regex,
  và **danh sách 3 tên đầu** đã bắt.

**Ba kết quả có thể xảy ra, và cả ba đều được chấp nhận:**

1. **> 0** → AC4 đóng, ghi số.
   **KẾT QUẢ ĐO THẬT 2026-09-28: = 0, nên AC4 KHÔNG đóng.**
   `docs/evidence/chain1-otes-2026-09-28.md`: 91 unit, parser 1.4.4, 63 UC,
   chain 1 = **0** finding, kèm chẩn đoán bằng probe: 91/91 unit trích được
   entity, 28 stem, đúng **một** cluster đạt ≥2 mục nhưng chỉ có **một**
   original (`We`) nên bị cổng ≥2-original chặn **đúng**. Tức check chạy và đọc
   được văn bản; tài liệu chỉ không có hình dạng mà check nhắm tới. Tiêu chí
   "**> 0**" sửa thành: *đo trên tài liệu thật và ghi số kèm lý do* — một tiêu
   chí đòi con số dương trên tài liệu không có dữ liệu đó chỉ dạy repo này một
   thói quen xấu: bịa metric. Phạm vi của check đã ghi vào
   `review-rules/adapters/app-port-map.md`.
2. **= 0** → nghĩa là regex đúng nhưng nguyên nhân gốc **không phải regex**.
   Khi đó phải tìm nguyên nhân thật (nhiều khả năng: `_extractEntityName` chỉ lấy
   từ đầu, hoặc điều kiện "2 mục khác nhau" hiếm gặp trong OTES), **không** sửa
   tiếp regex cho tới khi biết.
3. **Crash hoặc tìm ra nhiều** → ghi vào evidence và **giữ nguyên code**, chờ quyết
   định riêng. Sửa theo phản ứng là cách làm mà `docs/roadmap.md` ROADMAP-AC2
   cấm.

**AC-B:** có file evidence với số thật, kể cả khi kết quả là 0. **"0" cũng là một
kết quả đo được; im lặng thì không phải.**

---

## 3. Phase C — Gold set (đóng M2, mở khóa cả chain 2/3/4–6)

Đây là việc **lớn nhất và giá trị nhất** trong plan này, và cũng là việc duy nhất
biến "AI nói có vấn đề" thành "AI tìm đúng N trên M vấn đề".

**Vì sao nó chặn cả những thứ khác:** `docs/roadmap.md:14` ghi M2 **MỞ** vì
chưa có bộ annotation để đo precision/recall. `scoring.md:104` định nghĩa
cross-artifact là **2/10 điểm** — tức là phần engine mà plan 9 vừa xây hiện
đang **không tính vào điểm** và **không được đo**. Chain 2/3 mới chỉ là *dòng
ledger*, chưa phải *kết quả có thứ hạng*.

**Cách làm, theo đúng thứ tự:**

1. **Chọn 1 tài liệu, 1 loại finding, 20–30 mẫu.** Không chấm cả 26 check.
   Đề xuất: chain 1 (đã có, rẻ, và có sẵn 285 reference finding ở
   `docs/evidence/qa-signoff-2026-09-14.md` làm mốc so).
2. **Người A dán nhãn `present` / `absent`** mà không xem output của AI.
3. **Người B dán lại độc lập** — đây là bước quyết định, và `RULEBOOK` đã có
   tiền lệ: hai người chấm chênh 1.4 điểm ở v1.5, được sửa bằng cách **viết rõ
   luật đếm** chứ không phải bằng cách tranh luận.
4. Chỉ khi hai người **khớp trên ≥ 80%** mẫu thì mốc đó mới dùng làm gold.
   Dưới ngưỡng đó: gold set chưa đủ tin cậy, và đo precision/recall trên nó là
   đo cái không chắc.
5. Tính precision / recall của chain 1 (và chain 2/3 nếu đủ mẫu).

**AC-C:** có `docs/evidence/goldset-<loại>-2026-09-26.md` ghi: nguồn mẫu, số
mẫu, tỉ lệ khớp giữa hai người, precision, recall. **Số nào cũng được, kể cả
kém** — điều không được là không có số.

> **Cảnh báo phạm vi:** đây là việc cần **con người**, không phải code. Nếu thiếu
> người chấm độc lập, phase này **không thể làm một mình** — ghi vậy vào báo cáo
> thay vì tự dán rồi tự chấm, vì tự chấm là chữ ký của một gold set vô giá trị.

---

## 4. Phase D — P3 màn hình giáo viên (chỉ khi C có kết quả)

**Điều kiện tiên quyết:** C có precision/recall. Lý do: một màn hình giáo viên
hiển thị "⚠ 3 Issues / ✓ 12 Passed" mà **không ai đã đo độ chính xác** thì đang
đưa con số không đã kiểm chứng vào giao diện người dùng thật.

- Dùng `AppRole.teacher` + `AppRoleScope` đã có (ADR 0015) — `AppPlatform` **không
  đụng**, có test bảo vệ.
- Màn hình tối thiểu, theo workflow giáo viên: danh sách submission → chi tiết một
  submission → đọc report → Approve / Request Revision.
- Nguồn dữ liệu: `GET /submissions/{id}` (P2) — **không** thêm endpoint mới.
- Điện thoại phải hiện điểm chưa đo được là *chưa đo*, không phải điểm tốt.
  Nếu precision < 0.6 thì hiện cảnh báo "kết quả chưa được kiểm định" ngay trên
  màn hình.

**AC-D:** shell giáo viên có test; `test/desktop/app_breakpoint_test.dart` (9 bề
rội) xanh; có test ở 390×844.

---

## 5. Phase E — P4 (không làm, và ghi lý do)

`Group` / `Schedule` / `Notification` là CRUD thuần. Plan 9 đã cảnh báo và tôi
giữ nguyên lập trường đó: chúng **không đo được gì về AI**, và chúng đòi ba quyết
định hạ tầng chưa có:

1. **Host.** `settings.py:143` tự thừa nhận filesystem serverless chỉ ghi được
   ngoài `/tmp`. Submission trên Vercel **mất mỗi cold start**. Không sửa được bằng
   config.
2. **Quota.** 50/ngày **mỗi người** (`settings.py:67`). Giáo viên chấm 20 nhóm × 2
   vòng là vượt ngày đầu.
3. **Identity.** Không có bảng user nào. Capability-URL đủ cho demo, **không đủ**
   cho "5 nhóm đang chờ review".

Nếu vẫn muốn làm, thứ tự đúng là **1 → 2 → 3**, và mỗi bước là một ADR riêng.
Làm UI trước rồi chọn host sau là dựng trên cát.

---

## 6. Rủi ro của chính plan này

- **Phase C có thể không làm được** vì thiếu người chấm độc lập. Đó không phải
  lý do bỏ; đó là việc phải nói ra, và nó chặn D.
- **Số liệu sẽ xấu.** Chain 1/2/3 trên OTES nhiều khả năng có precision thấp —
  nhiều phát hiện là *tín hiệu*, chưa phải *lỗi*. Một kết quả xấu có số đo **giá
  trị hơn** một kết quả đẹp không có số: nó cho biết cần sửa luật đếm hay sửa
  mô hình.
- **Phạm vi bị hút.** Phase A và B đủ cho một lượt. C là một sprint. Đừng mở D
  khi C chưa có kết quả, dù D trông thú vị hơn nhiều.

---

## 7. Acceptance Criteria chung

| # | Tiêu chí | Cách kiểm |
|---|---|---|
| **AC-10.1** | Chain 3 có test ở tầng service | 4 ca A1–A4; A2 và A3 phải **không** sinh row |
| **AC-10.2** | AC4 đo trên tài liệu thật | evidence có số trước/sau, kể cả khi kết quả là 0 |
| **AC-10.3** | Hồi quy xanh | `cd app && flutter test`; `cd server && .venv\Scripts\python -m pytest tests\` — **qua venv** |
| **AC-10.4** | Guardrail xanh | `python tools\check_guardrails.py` 8/8 |
| **AC-10.5** | Không sửa guardrail trong im lặng | Mọi thay đổi luật ghi ADR (`docs/adr/README.md` số kế tiếp **0016**) |
| **AC-10.6** | Không nâng finding lên thang điểm khi chưa có gold set | `requiresVisionEvidence` giữ nguyên; verdict không cộng chain 2/3 |

## 8. Bắt đầu

1. **Phase A** — 4 test, không sửa `lib/` trừ khi test lộ lỗi thật.
2. **Phase B** — chạy `ContradictionPass` trên OTES thật, viết evidence.
3. Dừng lại, đọc lại hai file evidence, **rồi** quyết định C.

Không làm D và E trong lượt này.
