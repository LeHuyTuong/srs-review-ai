# Kết luận ba lần chạy → output và workflow cho `srs-review-ai`

**Ngày:** 2026-09-15 · **Rulebook:** 1.5-draft · **Nguồn:** ba ledger trong `reviews/`
Tài liệu này chốt **app phải xuất ra cái gì** và **chạy theo trình tự nào**, dựa trên bằng chứng đo được, không dựa trên phỏng đoán.

---

## 0. Ba lần chạy — kết quả

| Tài liệu | Loại | Điểm 1.5 | Trạng thái | Finding | Ledger |
|---|---|---|---|---|---|
| OTES SRS (mục C) | SRS | **4.5**/10 | NOT DONE | 96 (67 red) | `OTES-…-rescore-v0.2.md` |
| OTES SDS (mục D) | SDS | **3.1**/10 | NOT DONE | — | như trên |
| HisWise-RAG | SDS | **4.9**/10 | NOT DONE | 32 (12 red) | `HisWise-SDS-…-ledger.md` |
| **CarbonX** | SRS | **1.7**/10 | NOT DONE | **43 (24 red)** | `CarbonX-SRS-…-ledger.md` |

**Hai SRS chênh 2.8 điểm** (OTES 4.5 · CarbonX 1.7) — lần đầu thang SRS được thử trên hai mẫu và nó phân biệt được. Bốn tài liệu trải 1.7 → 4.9.

CarbonX thêm ba bài học rulebook (R13 S4 quá hẹp · R14 thang không thưởng định lượng đặt sai mục · R15 tỉ lệ hình không đọc được nên tách "sơ đồ phân tích" khỏi "ảnh chụp") — chi tiết ở phụ lục ledger của nó. **Và nó là tài liệu đầu tiên vi phạm hard rule 9**: email cá nhân thật trong ảnh admin.

Thang điểm qua bốn phiên bản, để thấy nó ổn định dần:

| | v0.1 | v0.2 | v0.2.1 | **1.5** |
|---|---|---|---|---|
| OTES SDS | 0.0 | 1.4 | 2.7 | **3.1** |
| HisWise SDS | — | — | 3.7 | **4.9** |
| Chênh lệch | — | — | 1.0 | **1.8** |

**Cả ba đều dưới ngưỡng đạt 5.0.** Điều đó có nghĩa: **nửa trên của thang chưa được kiểm chứng lần nào.** Ghi rõ ở §6.

---

## 1. Đơn vị output của app đang sai

App hiện chấm **từng requirement** (mỗi dòng 0–10, `contracts/review.schema.json`). Nhưng đọc lại 128 finding của ba lần chạy: **những lỗi quyết định chất lượng tài liệu đều ở cấp artifact hoặc cross-artifact**, không ở cấp dòng.

| Loại finding | Đếm được ở cấp dòng? | Ví dụ thật |
|---|---|---|
| Không có RTM | ❌ | cả 3 tài liệu |
| Không có ADR | ❌ | OTES 0/9, HisWise 0/12 |
| Sequence không khớp class | ❌ | OTES 0/40 message |
| Thiếu mục (Intro, Interface design) | ❌ | HisWise thiếu 2/5 |
| Hình không có caption / dòng đọc-hiểu | ❌ | HisWise 0/18 |
| ID trùng, sai mẫu | 🟡 một phần | OTES `UC04` dùng cho 8 UC |
| Câu mơ hồ, NFR không số | ✅ | OTES 44/44 |

Chỉ **một** trong bảy nhóm chấm được ở cấp dòng. Một điểm per-requirement không bao giờ nói được "hình này tả một hệ thống khác với hình kia".

**Quyết định:** output chính của app là **ledger artifact-level + verdict**, theo `review-rules/checklists/ledger-format.md`. Điểm per-requirement tụt xuống thành **một đầu vào** của tiêu chí S5 (tỉ lệ FR sạch), không còn là kết quả.

---

## 2. Check giá trị cao nhất đều THUẦN TEXT — và app chưa có cái nào

Xếp hạng theo (khả năng phân biệt × chi phí). "Phân biệt" đo bằng: tiêu chí này có tách được HisWise khỏi OTES không.

| # | Check | Phân biệt | Chi phí | App có? |
|---|---|---|---|---|
| 1 | **chain 3** — lifeline/message ↔ class/operation | **0.12 vs 0.70** — mạnh nhất | text thuần, so tên | ❌ |
| 2 | **techWithoutAdr** — tên công nghệ không có ADR | OTES 0/9 · HisWise 0/12 | text, regex + từ điển | ❌ |
| 3 | **missingSection** — khung 7 mục / A–F | OTES 0.80 vs HisWise 0.60 | text, so heading | ❌ |
| 4 | **G1/G2** — caption có tên loại + 3–5 câu đọc-hiểu | HisWise 0/18 · OTES 0/94 | text, regex caption + đếm câu | ❌ |
| 5 | **idFormat** — `FR-EPIC-NN` / `UC-NNN` / `NFR-CAT-NN` | cả 3 tài liệu fail | regex | ❌ |
| 6 | **nfrUnquantified** — NFR không số / không điều kiện đo | OTES 0/11 | text, tìm chữ số + đơn vị | ❌ |
| 7 | **rtmOrphan** — phát hiện **không có RTM** | cả 3 fail | text, tìm heading | ❌ |
| 8 | **chain 4** — cột trạng thái ↔ enum ↔ state machine | OTES 0/12 · HisWise 0.5/4 | text, so tập tên | ❌ |
| — | *Diagram notation (mũi tên, cardinality, initial node)* | yếu | **vision, đắt, 4/18 hình HisWise không đọc nổi** | 🟡 có |

**Kết luận nặng ký nhất của cả ba lần chạy:** app đang đầu tư vào ô yếu nhất (vision đọc notation) và bỏ trống tám ô mạnh nhất — tất cả đều là so chuỗi. Không cần quota, không cần model, chạy offline được.

Bằng chứng phụ: 4/18 hình của HisWise **không đọc được ở cỡ in** (~2pt), và 5 hình của OTES cũng vậy. Vision không cứu được hình mà chính con người cũng không đọc nổi.

---

## 3. Workflow: hai pass, không phải một

Hiện tại app gọi LLM per-requirement ngay từ đầu — đốt quota vào tín hiệu ít phân biệt nhất.

```
PASS A — deterministic, offline, không quota
  A0  Kiểm kê: trang · hình · bảng UC · ADR · endpoint · trích mọi ID
  A1  missingSection      (khung A–F / 7 mục)
  A2  idFormat            (3 mẫu ID)
  A3  nfrUnquantified     (NFR có số + điều kiện đo)
  A4  N/A hàng loạt       (quality-rules §E, đếm theo trường)
  A5  techWithoutAdr      (danh sách công nghệ vs heading ADR)
  A6  rtmOrphan           (có RTM không → gate NOT DONE)
  A7  G1/G2/G8a           (caption + dòng đọc-hiểu + số hiệu duy nhất)
  A8  chain 1, 3, 4       (so tên: naming drift · lifeline↔class · status↔enum)
  → ledger nháp + verdict sơ bộ + danh sách hình CẦN vision

PASS B — LLM, có quota, chỉ chạy phần A không làm được
  B1  Hình trong danh sách A7/A8 → vision, theo câu hỏi của loại đó
  B2  Đoạn văn nghi WHAT-only → hỏi "trả lời câu nào trong 4 câu HOW?"
  B3  Câu nghi mơ hồ mà phrase-list không bắt → ngữ nghĩa
  B4  info: necessary / feasible / correct
  → bổ sung ledger, chốt verdict
```

Ba lý do trình tự này đúng:

**Pass A một mình đã ra được verdict có nghĩa.** Trên HisWise, A1+A5+A6+A7 chiếm 8/12 red. Trên OTES SDS, tương tự. Người dùng thấy kết quả trong vài giây, không tốn quota.

**Pass A quyết định Pass B tiêu bao nhiêu.** A7 biết hình nào thiếu caption, A8 biết class nào thiếu — nên B1 chỉ gửi hình *cần* chấm, không gửi cả 94 hình. Đây là cách duy nhất sống được với 50 request/ngày.

**Pass A chạy được khi không có mạng.** Đúng với ràng buộc "local thôi, cloud không được biết" đã chốt từ đầu.

---

## 4. Output format — đã chốt, không bàn lại

Ledger 9 cột + verdict block sống sót qua 3 lần chạy và 3 vòng kiểm chéo độc lập. `review-rules/checklists/ledger-format.md` là bản chuẩn.

App cần đổi ba thứ ở `report_export.dart` để khớp:

| Hiện tại | Cần |
|---|---|
| Thiếu cột **Quote**, **Rule**, **Suggested rewrite** | Thêm — Quote là hard rule 1, không có quote thì xoá dòng |
| Severity `high/medium/low` | Map cố định `high→red`, `medium→amber`, `low→info` |
| Verdict pass/fail theo bucket | Verdict liên tục: `sàn = 5 × trung bình có trọng số`, in **phân số từng tiêu chí** |

Giữ nguyên "three twins" MD/JSON/HTML — kiến trúc đó đúng, chỉ đổi nội dung cột.

---

## 5. Scoring: năm chỗ `document_verdict.dart` cần sửa

Ba chỗ đã ghi ở `scoring.md` §9 từ v0.2.1, cộng hai chỗ mới từ lần chạy HisWise:

1. **Sàn 7 bucket all-or-nothing** → 5 tiêu chí tỉ lệ (SRS) / 4 tiêu chí (SDS). Một `ucSize` amber không được làm sàn = 0.
2. **Trừ theo ledger row, prefix `FLOW-`** → prefix đó **không bao giờ được sinh** (family thật là `SM`/`SEQ-CLS`), nên lỗi sequence/state chưa từng bị trừ.
   **Đã sửa một nửa (2026-09-15):** prefix nay là hằng `deductingFamilies = ERD- / SM- / SEQ-CLS-`, kèm test bắt buộc mọi prefix phải khớp một `DiagramKind.family` thật — để không ai dựng lại đúng lỗi này. **Cố ý CHƯA làm nửa còn lại** ("bỏ trừ theo row, phạt chỉ còn ở hard rule 9/10") vì nó đi cùng việc thay cả sàn sang thang tỉ lệ ở mục 1; sửa riêng một mình sẽ làm mọi tài liệu **mất** phần phạt mà chưa có gì thay thế. Hai việc phải cùng một PR.
3. **Traceability null vĩnh viễn** → bật khi có `rtmOrphan`, ceiling lên 10.
4. **(mới)** **D3 trọng số ×2** trong sàn SDS. Lý do đo được: ở 1.4, OTES **thắng** HisWise ở sàn (2.66 vs 1.85) dù chain 3 là 0.12 vs 0.70 — vì 3/4 tiêu chí sàn chỉ hỏi "mục có tồn tại không".
5. **(mới)** **D4 = `n/a` khi không được cấp SRS**, loại khỏi trung bình thay vì cho 0. Cho 0 là phạt tài liệu vì thiếu sót của bộ test.

Đi kèm: `rubric.json` bump `v2 → v3` (weights `.25/.40/.20/.15` theo Q6, bỏ trần `uc_count`), sửa 2 test pin. Chi tiết file-by-file ở `review-rules/adapters/app-port-map.md` §5.

---

## 6. Trạng thái calibration — trung thực

| Câu hỏi | Trả lời |
|---|---|
| Rulebook bắt được tài liệu xấu? | **Có, đã chứng minh** — OTES 96 finding, CarbonX 43, mọi cái có quote |
| Phân biệt được hai tài liệu cùng loại? | **Có** — SDS: 3.1 vs 4.9 (chênh 1.8) · SRS: 4.5 vs 1.7 (chênh 2.8). Mỗi loại đã có 2 mẫu |
| Bắt được tài liệu tốt mà không đánh oan? | **Chưa biết** — HisWise là tài liệu tốt nhất đã chạy và vẫn 4.9. **Chưa tài liệu nào vượt 5.0** |
| Nửa trên của thang (5–10) đúng chưa? | **Chưa kiểm lần nào** |
| Chạy hai lần cùng tài liệu ra cùng kết quả? | **Chưa đo** |
| Giảng viên chấm cùng tài liệu có ra số tương tự? | **Chưa ai làm** — đây là calibration duy nhất đáng kể |

Ba việc đóng được ba khoảng trống trên, theo thứ tự rẻ→đắt: (a) chạy lại HisWise lần hai, diff hai ledger theo cột ID+Quote; (b) tìm **một SRS/SDS đã được hội đồng cho điểm cao** và chạy — nếu nó vẫn < 5.0 thì thang sai chứ không phải tài liệu; (c) nhờ một giảng viên chấm HisWise rồi so.

**Đừng công bố điểm cho sinh viên trước khi làm xong (b).** Ledger (danh sách lỗi có quote) thì dùng được ngay — nó không phụ thuộc hiệu chuẩn thang.

---

## 7. Thứ tự làm — từ đây tới xong

| # | Việc | Chặn bởi | Giá trị |
|---|---|---|---|
| 1 | **chain 3** `CheckId.seqClassOrphan` | — | Cao nhất. Text thuần, tách 0.12 vs 0.70 |
| 2 | `idFormat` · `nfrUnquantified` · `missingSection` | — | Ba rule đang red trong rulebook mà app im lặng |
| 3 | Ledger 9 cột + severity map ở `report_export.dart` | — | Output khớp chuẩn |
| 4 | Thang liên tục ở `document_verdict.dart` (5 chỗ §5) | shell để chạy test | Điểm hết vô nghĩa |
| 5 | `rubric.json` v3 + 2 test pin | shell | Q1 + Q6 đã ký |
| 6 | `techWithoutAdr` · `rtmOrphan` · G1/G2/G8a | — | Nhóm text còn lại |
| 7 | chain 4 (status↔enum↔SM) | — | Text, so tập tên |
| 8 | Pass A/Pass B tách đôi trong `review_repository.dart` | 1–7 xong | Tiết kiệm quota, chạy offline |
| 9 | `DEPLOYMENT` + `ACTIVITY` DiagramType, G6a/G6b | vision quota | Notation, giá trị thấp nhất |

**Việc 1–3 và 6–7 không cần shell, không cần quota, không cần vision.** Đó là phần lớn giá trị.

---

## 8. Đang bị chặn

**Shell sandbox chết** cả session (9 lần fail liên tiếp, lỗi mount symlink). Hệ quả:
- Không chạy được `pytest` / `flutter test` → việc 4, 5 phải chờ.
- Không đọc được `.docx` → **đã gỡ**: Amy export CarbonX sang PDF, chạy xong, kết quả ở `reviews/CarbonX-SRS-2025-09--2026-09-15-ledger.md` (1.7/10).

Chỉ còn `pytest`/`flutter test` bị chặn; việc 1, 2, 3, 6, 7 vẫn làm được ngay.
