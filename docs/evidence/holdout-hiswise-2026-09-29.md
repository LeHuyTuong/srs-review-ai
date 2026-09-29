# WP8 gate 3 — holdout HisWise: pipeline chạy thật được, và holdout phát hiện một lỗ hổng phân đoạn

**Ngày:** 2026-09-29 · **Chi phí đã duyệt:** 7 unit ≈ 2 batch call (đã tiêu đúng mức đó,
không hơn) · **Lượt 2 (cùng ngày, sau khi lọc footer):** ≤ 4 unit đã duyệt — đã tiêu
**đúng 4 unit, 1 batch call**. **Kết luận:** end-to-end chạy sạch (7/7 unit, 0 fail, 0 quote bị loại,
14 findings verify — 12 exact + 2 fuzzy), nhưng holdout **không chứng minh được thang
điểm ổn định tuyệt đối** — nó chứng minh được cái khác có giá trị hơn: bộ phân đoạn
của app **mù với hình dạng SDS kiểu HisWise**.

## Lượt 2 — cùng pipeline sau khi lọc unit footer (b246d18)

Dump giờ đi qua **unitFromRequirement** (bộ dựng inventory thật của app, không nhân bản
luật sang Python) và driver chỉ gửi unit `selected`; 3 unit footer bị giữ lại **có in tên
+ lý do** (`SEC-1-p5` footer-only 17 ký tự · `SEC-5` 9 · `SEC-6` 29):

| Đại lượng | Lượt 1 (7 unit) | Lượt 2 (4 unit gửi) |
|---|---|---|
| unit_ok / failed | 7 / 0 | **4 / 0** |
| findings (sum issues) | 14 | **5** |
| finding trích "Page \| N" | **≥ 3** | **0** |
| dropped_quotes | 0 | 0 |
| verification | 12 exact + 2 fuzzy | **5 exact** |
| Điểm các unit nội dung (SEC-1/2/3/4) | 4 / 4 / 4 / 3 | **6 / 7 / 8 / 5** |
| Điểm trung bình (toàn mẫu gửi) | 2,14 | **6,50** |

Nhiễu giảm đúng như kỳ vọng: **0 finding "Page \| N"** (lượt 1: ≥3, chiếm 21% findings);
trung bình điểm tăng 2,14 → 6,50 **không phải do model chấm dễ hơn** — mà là do mẫu số
bỏ 3 unit rác 0 điểm; so đúng cặp 4 unit nội dung thì 4/4/4/3 → 6/7/8/5.

**Hai sự thật phải nói thẳng về lượt 2:**

1. **Cache của lượt 1 đã bị tôi xoá** — sau lượt 1 tôi dọn proxy bằng
   `rm cache.sqlite3-wal`, mà 7 kết quả lượt 1 còn nằm trong WAL chưa checkpoint; lượt 2
   vì thế **cache miss cả 4 unit** (`cached=False` mọi unit) và trả tiền đúng 4 unit (1
   batch call, đúng trần duyệt). Bài học: **dọn tắt proxy bằng `clear()`/xoá file
   cache là xoá tiền thật** — chỉ xoá khi chắc chắn không cần kết quả nữa; WAL là một
   phần của database, không phải rác.
2. **Cùng 4 unit, hai lượt chấm, điểm chênh +2/+3/+4/+2** (4/4/4/3 → 6/7/8/5, cùng
   model `gemini-3.5-flash-lite`, cùng prompt p5). Đây là phép đo **độ lặp lại của
   model** trên tài liệu thật, cùng loại số lệch 1,4 điểm mà ledger HisWise vòng 1 đo
   được giữa hai lần chấm thủ công. Không kết luận gì thêm từ 2 điểm dữ liệu — nhưng
   nó là lý do chính đáng để nghi ngờ mọi con số điểm đơn-lượt, và là đầu vào cho
   holdout nhiều lượt sau này.

## Số đo lượt chấm 1 (in bởi driver, đếm findings bằng cách cộng issues qua results[])

| Đại lượng | Giá trị |
|---|---|
| unit_ok / failed | **7 / 0** |
| findings (sum issues) | **14** |
| dropped_quotes | **0** |
| verification | exact 12 · fuzzy 2 · **reordered 0** |
| severity | high 11 · medium 3 |
| type | incomplete 9 · vagueness 3 · untestable 2 |
| Điểm từng unit | SEC-1 4 · SEC-1-p5 **0** · SEC-2 4 · SEC-3 4 · SEC-4 3 · SEC-5 **0** · SEC-6 **0** |
| **Điểm trung bình** | **2,14** |
| mock / contract | false / **1.1.0** |

Điểm chấm lên đúng 3 unit rác (rác loại 1): `SEC-1-p5` = `"Page | 5 Page | 6"`,
`SEC-5` = `"Page | 13"`, `SEC-6` = `"Page | 14 Page | 15 Page | 16"` — 3 unit, 3
điểm 0, 3 finding "Page | …" không có nghĩa. **Nhiễu rác chiếm 3/14 = 21% findings.**

## Phát hiện cấu trúc: HisWise-style SDS không có ID prefix → parser mù use case

Text layer của trang 7 (`%TEMP%\hiswise_pages.json`, PyMuPDF) hiện **nguyên vẹn
bảng UC**: `2. Use cases` → `ID | Feature | Use Case | Use Case Description` →
`01 | Authentication | Login | Allows students and administrators…`. Nhưng ID
của bảng là **số trần `01`**, không phải `UC-01`; regex `_idAtLineStart` /
`_idAnywhere` của `RequirementSplitter` 1.4.4 chỉ nhận `UC|FR|NFR|BR|SR|NF|F-`,
nên **không dòng nào mở unit**. Toàn bộ bảng UC (và bảng package p9, bảng table
description p12) chảy vào buffer của section như văn xuôi:

| Unit | Nội dung thật | Số ký tự | Số unit mà nó đáng lẽ là |
|---|---|---|---|
| SEC-2 | §2 Use cases + bảng UC (01–… với mô tả đầy đủ) | 2 269 | ~một unit/UC |
| SEC-3 | §3 Code Packages + bảng package | 1 952 | ~một unit/package |
| SEC-4 | §4 Database Design + bảng Table Description | 1 157 | ~một unit/bảng |
| SEC-5, SEC-6 | §5 State Machine, §6 Sequence — **chỉ có tiêu đề** (sơ đồ là hình) | 9 / 29 | unit sơ đồ placeholder |
| SEC-1-p5, SEC-5, SEC-6 | footer trang tách thành unit | 17 / 9 / 29 | không unit nào |

Tức là trên tài liệu **không dùng ID prefix chuẩn**, hành vi "parser chỉ đọc dòng
có ID" **tái hiện đúng một lần nữa** — lần này ở tầng ID-format, không phải tầng
section-heading như 1.4.x đã vá. `SEC-2` 4/10 với finding "may perform soft
delete" là model chấm **cả bảng UC như một đoạn văn** — tín hiệu còn lại nhưng
mất khả năng truy vết từng UC.

## Đối chiếu với ledger 2026-09-15 — chỉ so được CHIỀU, không so được số

| | Ledger (manual, rulebook 1.6, vòng 2) | Holdout app này |
|---|---|---|
| Đối tượng chấm | **Artifact-level** theo rulebook (sàn 5 + diagram + cross-artifact + RTM) | **Per-unit** (lượt 1: 7 section unit; lượt 2: 4 unit sau lọc footer) |
| Người/model | hai agent chấm mù | gemini-3.5-flash-lite qua pipeline app |
| Điểm | **4,58 / 4,84** (lệch 0,26 — ĐẠT) | **2,14** (lượt 1, 7 unit) · **6,50** (lượt 2, 4 unit sạch) |
| Verdict | NOT DONE | (app không chấm verdict) |

**Ba lý do KHÔNG được đọc 2,14 (hay 6,50) vs 4,58/4,84 là "thang điểm lệch":** (1) mẫu số
khác hẳn — unit section so với artifact toàn tài liệu; (2) 0,5
điểm trên thang manual đến từ diagram/cross-artifact mà đường text-only này
không có; (3) điểm per-unit của app và điểm rulebook không cùng hệ quy chiếu. Cái so
được là **chiều**: HisWise tệ hơn OTES trên cùng pipeline (lượt 2 của HisWise 6,50
trên 4 unit vs OTES 5,8 trên 91 unit — gần nhau, khác với chiều ledger manual vốn
cũng gần nhau), và kết luận NOT DONE của ledger vẫn là khung đọc đúng cho cả hai.

## Kết luận cho gate 3

- **Đạt phần cơ chế**: holdout đúng nghĩa đã chạy được — hai lượt thật (7 unit + 4
  unit sau lọc footer), 0 fail, 0 quote bịa, chi phí đúng phê duyệt (7 + 4 unit).
  CarbonX vẫn thiếu file gốc.
- **KHÔNG đạt phần "thang điểm ổn định"** — và lượt 2 cộng thêm một bằng chứng: cùng
  4 unit chấm hai lần chênh +2/+3/+4/+2 điểm, tức **bản thân model đơn-lượt không
  ổn định** ở cấp unit. Đo độ ổn định thật cần nhiều lượt trên nhiều unit — việc của
  holdout nhiều vòng sau này, không của một lượt. Điều kiện tiên quyết phân đoạn
  vẫn chưa có: **bộ phân đoạn cần nhận diện bảng-ID-số-trần** trước khi holdout nào
  đo được sạch hoàn toàn (footer đã lọc xong — `b246d18`). Ghi vào
  `review-rules/adapters/app-port-map.md` và để một quyết
  định riêng (sửa parser = thay đổi hành vi chấm, cần gold set làm trọng tài —
  WP7 vẫn chờ hai người ký).

## Lệnh tái chạy

```sh
# 1. pages JSON (PyMuPDF, host):
python docs/evidence/scripts/_dump_pages.py   # hoặc fitz như chain1 evidence
# 2. units qua parser + inventory mapping của app (in số bị bỏ chọn):
cd app && flutter test test/hiswise_units_dump_test.dart   # in HISWISE: ... bo-chon=3
# 3. proxy với .env thật:
cd server && .venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
# 4. holdout (in unit_ok/failed, findings=sum issues, scores, verif):
python docs/evidence/scripts/hiswise_holdout_batch.py
```
