# Quality rules — tính chất của một requirement viết đúng

Áp cho từng dòng FR / UC step / NFR. Mỗi luật ghi: **cách nhận biết** (deterministic được không) và **check tương ứng trong app** nếu có (`CheckId` trong `app/lib/data/models/deterministic_finding.dart`).

## A. 9 (+1) tính chất — Wiegers / ISO 29148

| # | Tính chất | Câu hỏi reviewer đặt | Deterministic? | App CheckId | Severity khi fail |
|---|---|---|---|---|---|
| 1 | **Atomic** | Câu này có đúng MỘT hành vi? Có chữ "and/or" nối hai yêu cầu khác nhau? | Một phần (đếm "and" giữa hai động từ) | — (LLM) | amber |
| 2 | **Unambiguous** | Hai người đọc có hiểu thành hai cách? Có từ mơ hồ (mục C)? | ✅ phrase list | `ambiguousWording` | amber; red nếu trong NFR |
| 3 | **Testable / Verifiable** | Tester viết được test case pass/fail không? Có số đo, có điều kiện kết thúc? | ✅ (thiếu measurement / thiếu postcondition) | `ambiguousWording`, `missingPostcondition` | red cho NFR, amber cho FR |
| 4 | **Complete** | Còn TBD / placeholder? Đủ actor, trigger, pre, post, alternatives? | ✅ | `placeholderTbd`, `missingActor`, `missingPostcondition` | red nếu TBD trong tài liệu nộp |
| 5 | **Consistent** | Cùng khái niệm gọi hai tên? Hai requirement mâu thuẫn? | ✅ naming drift; contradiction pass | `duplicateIds`, `crossArtifactName` | red khi mâu thuẫn logic |
| 6 | **Traceable** | Có ID đúng mẫu (RULEBOOK §4)? Có xuất hiện trong RTM? | ✅ format + RTM | `duplicateIds` (uniqueness); **format ID chưa check trong app** | amber |
| 7 | **Prioritized** | Có Priority (MoSCoW / High-Med-Low)? Toàn tài liệu có cột priority không? | ✅ document-level | `missingPriority` | amber |
| 8 | **Necessary** | Bỏ dòng này hệ thống có kém đi không? Gold-plating? | ❌ cần hiểu nghĩa | — (LLM/human) | info |
| 9 | **Feasible** | Làm được trong 14 tuần với stack đã chọn? | ❌ | — (LLM/human) | info |
| 10 | **Correct** | Đúng ý stakeholder? Chỉ stakeholder trả lời được. | ❌ | — (human) | info |

Reviewer tự động **không được** phán 8–10 là fail; chỉ nêu nghi vấn dạng câu hỏi.

## B. NFR — bắt buộc định lượng, phân nhóm ISO/IEC 25010

Mẫu câu NFR hợp lệ: `<Hệ thống> SHALL <hành vi đo được> <ngưỡng số> <điều kiện đo>`.
Ví dụ pass: "The API SHALL respond to 95% of search requests within 800 ms under 200 concurrent users."
Ví dụ fail: "The system should be fast and reliable."

| CAT (dùng trong `NFR-<CAT>-NN`) | ISO 25010 characteristic | Thước đo tối thiểu chấp nhận |
|---|---|---|
| FUNC | Functional suitability | % coverage FR, tỉ lệ đúng |
| PERF | Performance efficiency | latency (ms, percentile), throughput (req/s), tài nguyên (MB, %CPU) |
| COMP | Compatibility | danh sách phiên bản OS/browser/API cụ thể |
| USAB | Usability | thời gian hoàn thành task, số bước, tỉ lệ lỗi người dùng, WCAG level |
| RELI | Reliability | availability % (vd ≥ 99.5%), MTBF, RPO/RTO |
| SECU | Security | chuẩn (OWASP Top 10, TLS 1.2+), thời gian lock, độ dài token, log retention |
| MAIN | Maintainability | test coverage %, cyclomatic complexity, thời gian deploy |
| PORT | Portability | số platform, thời gian cài đặt |

Luật: NFR không có **số** hoặc không có **điều kiện đo** → red `SRS` (RULEBOOK hard rule 6). NFR không xếp được vào 8 CAT → amber, hỏi lại.

## C. Ambiguity scan — chạy trước khi đóng file

Danh sách phrase song ngữ, so khớp trên text đã fold (NFC/NFD/U+2028 — `text_fold.dart`). Đây là **superset** của list trong `quality_checks.dart` (app có ít hơn, có chủ đích); thêm phrase vào app phải kèm ví dụ thật trong một SRS, không thêm theo cảm giác (bài học OTES: "all"/"some" bỏ có chủ đích vì false-positive).

| Nhóm | EN | VI | Thiếu gì |
|---|---|---|---|
| Vague quantifier | several, various, many, few, appropriate, adequate, sufficient, as needed, etc. | nhiều, một số, phù hợp, đầy đủ, khi cần, v.v. | số lượng |
| Vague quality | fast, quick, easy, user-friendly, robust, secure, reliable, efficient, flexible, seamless | nhanh, dễ dùng, thân thiện, ổn định, an toàn, hiệu quả, mượt | thước đo |
| Weak modal | should, may, might, could, if possible, where applicable | nên, có thể, nếu được | bắt buộc hay không (dùng SHALL) |
| Missing condition | "when necessary", "in some cases", "normally", "usually" | "khi cần thiết", "thường", "trong một số trường hợp" | điều kiện trigger |
| Missing actor | câu bị động không chủ ngữ: "data is validated", "notification is sent" | "dữ liệu được kiểm tra" | ai/thành phần nào làm |
| Unclear scope | "support", "handle", "process", "manage" đứng một mình | "hỗ trợ", "xử lý", "quản lý" | hành vi cụ thể |
| Placeholder | TBD, TBA, TODO, to be defined, ???, XXX | chưa xác định, đang cập nhật, sẽ bổ sung | nội dung |

Output của scan: bảng `ID | quote | nhóm | gợi ý viết lại` — gợi ý phải là câu hoàn chỉnh có số đo, không phải "hãy cụ thể hơn".

## D. Use case step — luật bổ sung (khớp `templates/use-case.md`)

- Mỗi step có đúng 1 Actor Action **hoặc** 1 System Response; không gộp.
- Exception mark inline `[Exception N]` tại step phát sinh; phần Exceptions liệt kê đủ N.
- Preconditions kiểm tra được trước khi chạy; Post-condition **Success** và **Fail** đều phải có (thiếu cả hai = `missingPostcondition`; thiếu riêng Fail = amber, app chưa tách — đề xuất `missingPostFail` trong port-map).
- 3–7 transaction cho UC medium (`ucSize`); < 3 nghi vấn quá nhỏ (gộp?), > 7 nghi vấn quá lớn (tách?) — chỉ amber ở mức từng UC, nhưng **tỉ lệ toàn tài liệu là một tiêu chí điểm** (`scoring.md` §3).

## E. "N/A hàng loạt" — trường bắt buộc bị vô hiệu hoá (thêm v0.2)

"N/A" ở **một** bản ghi là hợp lệ: có trường thật sự không áp dụng. "N/A" ở **phần lớn** bản ghi thì không còn nghĩa "không áp dụng" nữa — nó nghĩa là trường đó chưa được phân tích, và cấu trúc tài liệu đang nói dối về độ đầy đủ của mình.

Luật: với mỗi **trường bắt buộc** của một template (bảng use case, data dictionary, ADR, test case):

| Tỉ lệ bản ghi điền "N/A" / rỗng / dấu gạch | Kết luận |
|---|---|
| ≤ 20% | bình thường, không nêu |
| > 20% và ≤ 50% | amber — hỏi vì sao |
| **> 50%** | **red** — trường bắt buộc bị vô hiệu hoá trên diện rộng |

Áp cho cả biến thể: "N/A", "n/a", "None", "-", "—", ô rỗng, và tiêu đề mục có nhưng không có nội dung. — và **trường bắt buộc vắng mặt hoàn toàn khỏi mẫu bảng** (tệ hơn N/A: người đọc không biết là thiếu).

Khác với `placeholderTbd` (§C): TBD/TODO nghĩa là "sẽ điền sau"; N/A hàng loạt nghĩa là "coi như không cần điền". Hai lỗi khác nhau, cùng mức red khi ở quy mô lớn.

Ví dụ thật (OTES 2026-09-14): `Alternatives: N/A` ở **61/63** bảng use case (97%) → red; `Relationships: N/A` ở 15/23 bảng (65%) → red; mục `8. Algorithms` chỉ có chữ `N/A` → red (mục rỗng).

## F. Trang bìa & header/footer — "document furniture" (thêm 2026-09-23, bản 1.7-draft)

Mục A–E đo **câu requirement**; mục này đo phần in lặp ngoài requirement: trang bìa và dòng đầu/cuối trang. SRS sinh viên rất hay thiếu hoặc lệch phần này — ráp hai bản tài liệu, copy template của nhóm khác, quên sửa tên đề tài cũ. Mọi check theo-requirement và cả LLM pass (chỉ đọc text requirement) đều **mù** trước lỗi này, trong khi trang bìa là thứ đầu tiên hội đồng đọc. Cả hai check đều deterministic thuần text trên `pageTexts` — không LLM, không OCR.

### F.1 Trang bìa phải khai báo đủ ba trường — `coverPageInfo`

Trang bìa của tài liệu nộp phải khai báo: **tên đề tài**, **giảng viên hướng dẫn**, **nhóm/thành viên**.

Phát hiện deterministic: quét **nhãn trường** trên text đã fold (`text_fold.dart` — NFC/NFD/U+2028 về cùng ASCII) của **hai trang đầu** (template FPT đặt GVHD ở trang chữ ký ngay sau bìa); DOCX (một entry dẹt) thì đọc 2000 ký tự đầu.

| Trường | Nhãn chấp nhận (đã fold) | Severity |
|---|---|---|
| Tên đề tài | `project name` · `project title` · `topic:` · `title:` · `tên đề tài` / `đề tài` | **red** (app: high) |
| GV hướng dẫn | `supervisor` · `mentor` · `instructor` · `giảng viên hướng dẫn` · `hướng dẫn` · `GVHD` | amber (app: medium) |
| Nhóm / thành viên | `group` · `team` · `nhóm` · `thành viên` · `member` · `author` · `student` | info (app: low) |

**Heuristic, hai hướng sai đã biết, chấp nhận cả hai:** (a) chỉ kiểm NHÃN, không kiểm giá trị — bìa có dòng "Project name:" để trống vẫn pass (bảng Word dẹt ra có thể đặt giá trị ở dòng sau, đòi giá trị sẽ fail oan); (b) bìa in tên đề tài to **không nhãn** → báo thiếu nhầm (false positive). Giữ hướng này vì ngược lại (khớp "dòng chữ to" tự do) không kiểm soát được bằng text thuần. Bìa là ảnh scan (không có text layer, < 3 dòng đọc được) → check **im lặng**, không kết luận gì (hard rule 3: phần không đọc được không được gọi "clean"; coverage ledger là chỗ nói điều đó, không phải check này).

Ví dụ pass: bìa mẫu FPT — bảng `Project name: OTES`, `Supervisor: …`, `Group 1` + bảng Member. Ví dụ fail: bìa chỉ có logo + "Capstone Project Report 3" → 3 finding (thiếu cả ba trường).

### F.2 Header/footer lặp lại phải nhất quán — `headerFooterConsistency`

Header/footer là dòng xuất hiện ở **cùng một vị trí** (đầu/cuối) trên nhiều trang. Nội dung dòng đó **đổi giữa các trang** mà không phải đánh số → dấu hiệu ráp hai bản tài liệu (sót tên đề tài cũ, tên nhóm cũ).

Phát hiện deterministic trên 4 slot mỗi trang (2 dòng không-rỗng đầu + 2 dòng cuối; bỏ dòng toàn số trang kiểu `12`, `Page 12`, `Trang 12`; bỏ dòng < 4 hoặc > 120 ký tự; bỏ trang < 5 dòng — trang toàn hình, dòng "đầu" của nó là caption, không phải furniture):

1. Một dòng là **furniture** khi lặp lại ở cùng một slot trên ≥ max(3, 20% số trang lấy mẫu).
2. Hai biến thể furniture trong **cùng slot** → so token: trùng ≥ 60% (Jaccard) **và** khác ít nhất một từ **không phải chữ số** → finding **info** (app: low), nêu nguyên văn cả hai biến thể + số trang mỗi bên.
3. Khác nhau **chỉ ở chữ số** (`Chapter 3` / `Chapter 4`, `Report 2` / `Report 3`) → **bỏ qua có chủ đích**: đó là đánh số, và cũng là giới hạn — "Report 2" sót lại trong bản "Report 3" đúng ra là lỗi nhưng không tách nổi khỏi số chương bằng text thuần.

**False positive đã biết:** running head đổi theo chương mà trùng tiền tố dài (vd "Capstone Project — Current Situation" / "Capstone Project — Problem Definition": khác từ thật) → vì vậy severity **không bao giờ quá info/low** và message luôn dặn kiểm tra bằng mắt. Check chỉ nói khi tài liệu có **≥ 6 trang** lấy mẫu được; DOCX (1 entry) và PDF ngắn → im lặng. Không có OCR: PDF scan cho text rỗng → im lặng.

Ví dụ pass: 60 trang, dòng đầu mọi trang đều "Online Tutoring Examination System". Ví dụ fail: trang 1–30 ghi "Online Tutoring Examination System", trang 31–60 ghi "Online Testing Examination System" (khác từ "Tutoring"/"Testing") → finding nêu cả hai.

### F.3 Khai báo dự án phải khớp trang bìa — `projectInfoMismatch`

Người dùng khai báo thông tin đồ án ở form (tên đề tài, GVHD — `contracts/project-info.schema.json`). Mục này đối chiếu **vùng bìa** (định nghĩa y hệt §F.1: hai trang đầu, DOCX đọc 2000 ký tự đầu) với khai báo:

| Trường khai báo | Cách so (fold ASCII, §F.1) | Severity |
|---|---|---|
| Tên đề tài | token ≥ 4 ký tự của tên khai báo; khớp < 50% token xuất hiện trên bìa → finding | **red** (app: high) |
| GVHD | tên khai báo (fold) không xuất hiện nguyên chuỗi trên bìa → finding | amber (app: medium) |

- **Chỉ chạy khi có khai báo.** Chưa khai báo → không finding (§F.1 vẫn chấm bìa độc lập); form là tùy chọn, không được biến "chưa điền form" thành lỗi tài liệu.
- Bìa scan (< 3 dòng đọc được) → **im lặng** như §F.1 (hard rule 3).
- False positive đã biết: tên đề tài khai báo viết tắt ("OTES" thay vì "Online Tutoring Examination System") làm token khớp thấp → finding dặn kiểm tra bằng mắt chứ không khẳng định sai; ngược lại bìa dùng từ đồng nghĩa ("Capstone Project" vs tên khai báo) cũng có thể fail.
- Ví dụ pass: khai báo "Online Tutoring Examination System" + bìa in đúng chuỗi (hoặc ≥ 50% token). Ví dụ fail: khai báo "OTES SRS – Exam module" nhưng bìa ghi đề tài khác hẳn → 1 finding red.

### F.4 Chương phải theo đúng thứ tự — `sectionOrder`

Mục lục đã phân giải thành các dải chương (`SectionRange`: printed/pdf start–end). Nếu dải của một chương **bắt đầu trước khi chương liền trước kết thúc** (`pdfStartIndex` không tăng đơn điệu) → finding **amber** (app: medium): "Chương B bắt đầu ở trang X nhưng chương A còn tới trang Y" — dấu hiệu chèn lộn/chương lắp sai chỗ, hoặc mục lục lẫn.

- Chỉ chạy khi `blueprint.trusted` (mục lục phân giải được trang thật) — cùng gate với `captionPageMismatch`.
- Check này **không** phán "đủ khung mẫu" (việc của `missingSection`), chỉ phán **thứ tự**.
- Giới hạn: mục lục thiếu/không phân giải được → im lặng; tài liệu một chương không có gì để so.
- Ví dụ pass: A→B→C→D→E tăng đơn điệu. Ví dụ fail: chương D khai `pdfStartIndex` nhỏ hơn `pdfEndIndex` của C → 1 finding nêu cả hai dải.

### F.5a Heading đánh số phải tạo thành phân cấp — `headingNumbering`

Nhóm tiêu chí format & layout (font, cỡ chữ, căn lề, giãn dòng, đánh số trang, heading, caption, khoảng trắng). Chỉ hai đo được từ text trích xuất nên port trước; phần còn lại cần metric font/-layout của PDF hoặc vision — bảng "chưa port" ở cuối mục này, port-map ghi cùng.

Heading số `3.1` không thể tồn tại khi không có heading `3` — cũng vậy `4.2.1` cần `4.2`. Đọc các unit `SEC-<số>` mà parser đã tách (chỉ xét id khớp đúng mẫu `SEC-<đ số>(.<đ số>)*`; heading không đánh số im lặng):

1. **Thiếu cha**: child `SEC-a.b…` mà một tiền tố của nó (`SEC-a`, `SEC-a.b`, mọi tiền tố dài hơn 1 cấp) không xuất hiện → finding **amber** (app: medium), subject = id con, message nêu đúng cấp thiếu.
2. **Trùng số**: hai heading cùng một chuỗi số → finding **amber** (app: medium), subject = chuỗi số.

Giới hạn: id do parser gán — heading số thật mà parser không nhận ra thì check mù (cùng mọi check đọc unit); `1.10` sau `1.9` là bình thường (so theo chuỗi segments, không so số thập phân); tài liệu không đánh số → im lặng.

Ví dụ pass: 1, 2, 3, 3.1, 3.2, 4. Ví dụ fail: có 3.1–3.3 nhưng không có 3 → finding nêu "mục 3.1 cần mục 3".

### F.5b Số trang phải thấy ở dòng cuối — `pageNumbering`

Trên text trích xuất (không OCR, không layout thật), gate ≥ 6 trang như §F.2. Với trang 2..N (bỏ trang bìa 0): dòng cuối không-rỗng của `pageTexts[i]` là một số đứng riêng (`\d{1,3}`) hoặc `Page|Trang <n>` → trang đó "có số trang":

1. Không trang nào có số ở cuối → finding **info** (app: low), dặn kiểm tra bản in.
2. Có số nhưng chuỗi số lặp/giảm ở ≥ 3 vị trí → finding **info**: số trang không đơn điệu.

False positive đã biết: extractor có thể để footer ở giữa text ("dưới cùng" của text layer ≠ dưới cùng layout) → severity cố ý low + message luôn dặn **kiểm tra bằng mắt**; PDF scan không text → im lặng (hard rule 3).

### F.5 phần chưa port — cần evidence không phải text, đừng port giả

| Tiêu chí | Cần gì | Tầng |
|---|---|---|
| Font (thân vs heading, nhất quán giữa các trang) | span font name — PyMuPDF `page.get_text('dict')` | server `docmap.py` |
| Cỡ chữ (thang cỡ theo cấp heading) | span size theo dòng | server |
| Căn lề / giãn dòng / khoảng trắng | layout metrics | server (hoặc vision) |
| Caption tồn tại dưới MỌI hình/bảng (riêng số hiệu đã có ở G1/`numberingGap`) | figure bbox (docmap) ↔ dòng caption gần nhất | server text+bbox |

Các tiêu chí vào ledger người-reviewer/Claude tới khi server port (cùng lớn hard rule 9/10 giữ ở tầng người).

### F.6 Bảng/Hình bị dời ra xa vị trí mục lục khai báo — `tablePositionDrift`

Mục lục (`List of Tables` / `List of Figures`) khai bảng N ở **trang in P**, nhưng quanh trang đó (cửa sổ ±3 trang — cùng `captionSearchWindow` của builder) **không thấy caption**, trong khi `Table N` / caption text **tìm được ở nơi khác trong tài liệu**. Khác với `captionPageMismatch` (caption không thấy ở đâu → mục lục cũ/thôi), đây là **bảng bị dời** — điển hình: dời bảng xuống cuối mà quên Update Field. Spike 2026-09-23 (`docs/evidence/table-position-detection-2026-09-23.md`) mô phỏng `move_page(13 → 216)` bị bắt ngay (độ lệch +203 trang); file OTES sạch 217 trang: 114/114 caption trong cửa sổ → 0 finding.

Phát hiện deterministic, 0 token, chỉ chạy khi `blueprint.trusted` (cùng gate `captionPageMismatch`):

1. Builder: khi cửa sổ hụt thì quét **toàn thân tài liệu** (bỏ trang mục lục) — caption probe trước (đặc trưng hơn, tham chiếu chéo không paraphrase được), label `Table|Figure N` sau → thấy thì ghi `foundPageIndex`; **không** gán `pdfPageIndex` — phân giải vẫn thất bại đúng như cũ, mọi check đang chạy không đổi hành vi.
2. Finding **amber** (app: medium) khi `foundPageIndex` lệch trang kỳ vọng **nhiều hơn cửa sổ**: nêu trang in mục lục khai, trang in thật của caption, độ lệch ±k trang, và (khi cả hai chương rõ) caption nằm chương nào thay vì chương nào — đúng nghĩa "bảng bị dời xuống cuối tài liệu".
3. `captionPageMismatches` **bỏ qua** artifact đã có `foundPageIndex`: finding mới chính xác hơn, hai finding cho cùng một artifact là nhiễu. Caption không thấy ở bất kỳ đâu → vẫn `captionPageMismatch` như cũ.

Giới hạn (đo trên OTES 217 trang / 114 bảng, một tài liệu thật + một lượt mô phỏng move):

- Không có LoT/LoF (PDF không mục lục, DOCX không khái niệm trang) → im lặng.
- Bảng **không caption** không có định danh → check mù (cần `uncaptionedTable` server-side, chưa port; 96/187 trang OTES có vùng bảng không caption cùng trang).
- Tác giả renumber → label probe gãy; cả label lẫn caption probe gãy → rơi về `captionPageMismatch` (không bịa trang).
- Dời bảng **và** bấm Update Field → LoT đúng theo vị trí mới → check im lặng (không còn gì "sai"); chỉ diff 2 phiên bản bắt được — chưa có pipeline.
- Tham chiếu chéo trong text ("xem Table 12") trùng label ở trang khác có thể báo nhầm → caption probe chạy trước để giảm hướng này; message luôn dặn kiểm tra bằng mắt.
- Lệch ≤ 3 trang không thuộc check này (cửa sổ đã nuốt khi phân giải; giới hạn nhạy cố ý).

Ví dụ pass: OTES gốc — 114/114 khớp trong cửa sổ → 0 finding. Ví dụ fail: mục lục ghi `Table 1` ở trang in 11 nhưng caption nằm ở trang in 214 → 1 finding amber nêu cả hai trang + độ lệch +203.

### F.6 Bảng/Hình bị dời ra xa vị trí mục lục khai báo — `tablePositionDrift`

Mục lục (`List of Tables` / `List of Figures`) khai bảng N ở **trang in P**, nhưng quanh trang đó (cửa sổ ±3 trang — cùng `captionSearchWindow` của builder) **không thấy caption**, trong khi `Table N` / caption text **tìm được ở nơi khác trong tài liệu**. Khác với `captionPageMismatch` (caption không thấy ở đâu → mục lục cũ/thôi), đây là **bảng bị dời** — điển hình: dời bảng xuống cuối mà quên Update Field. Spike 2026-09-23 (`docs/evidence/table-position-detection-2026-09-23.md`) mô phỏng `move_page(13 → 216)` bị bắt ngay (độ lệch +203 trang); file OTES sạch 217 trang: 114/114 caption trong cửa sổ → 0 finding.

Phát hiện deterministic, 0 token, chỉ chạy khi `blueprint.trusted` (cùng gate `captionPageMismatch`):

1. Builder: khi cửa sổ hụt thì quét **toàn thân tài liệu** (bỏ trang mục lục) — caption probe trước (đặc trưng hơn, tham chiếu chéo không paraphrase được), label `Table|Figure N` sau → thấy thì ghi `foundPageIndex`; **không** gán `pdfPageIndex` — phân giải vẫn thất bại đúng như cũ, mọi check đang chạy không đổi hành vi.
2. Finding **amber** (app: medium) khi `foundPageIndex` lệch trang kỳ vọng **nhiều hơn cửa sổ**: nêu trang in mục lục khai, trang in thật của caption, độ lệch ±k trang, và (khi cả hai chương rõ) caption nằm chương nào thay vì chương nào — đúng nghĩa "bảng bị dời xuống cuối tài liệu".
3. `captionPageMismatches` **bỏ qua** artifact đã có `foundPageIndex`: finding mới chính xác hơn, hai finding cho cùng một artifact là nhiễu. Caption không thấy ở bất kỳ đâu → vẫn `captionPageMismatch` như cũ.

Giới hạn (đo trên OTES 217 trang / 114 bảng, một tài liệu thật + một lượt mô phỏng move):

- Không có LoT/LoF (PDF không mục lục, DOCX không khái niệm trang) → im lặng.
- Bảng **không caption** không có định danh → check mù (cần `uncaptionedTable` server-side, chưa port; 96/187 trang OTES có vùng bảng không caption cùng trang).
- Tác giả renumber → label probe gãy; cả label lẫn caption probe gãy → rơi về `captionPageMismatch` (không bịa trang).
- Dời bảng **và** bấm Update Field → LoT đúng theo vị trí mới → check im lặng (không còn gì "sai"); chỉ diff 2 phiên bản bắt được — chưa có pipeline.
- Tham chiếu chéo trong text ("xem Table 12") trùng label ở trang khác có thể báo nhầm → caption probe chạy trước để giảm hướng này; message luôn dặn kiểm tra bằng mắt.
- Lệch ≤ 3 trang không thuộc check này (cửa sổ đã nuốt khi phân giải; giới hạn nhạy cố ý).

Ví dụ pass: OTES gốc — 114/114 khớp trong cửa sổ → 0 finding. Ví dụ fail: mục lục ghi `Table 1` ở trang in 11 nhưng caption nằm ở trang in 214 → 1 finding amber nêu cả hai trang + độ lệch +203.

