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
