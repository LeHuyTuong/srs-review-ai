# P3+P4 · DEMO và PROOF — nội dung slide 17–24 + phụ lục A1–A6 (Guideline V11)

Nguồn: `docs/plans/13-defense-slides-roadmap-2026-11-10.md` §0, §3 (T10);
`docs/workflow/workflow-spec.md`; `docs/workflow/business-rules.md`;
`docs/workflow/rtm.md`; `docs/evidence/artemis-run-log.md`.

**Quy ước số.** Mọi con số dưới đây chép từ một trong các file trên và ghi kèm
`file:dòng` ở chân trang từng slide. Số **chưa đo được** để nguyên dạng ô vàng
`[CHỜ DEMO]` (phải chạy mới có) hoặc `[CẦN SỐ]` (phải đếm/đo mới có) — không suy
ra, không làm tròn thành đẹp. Không dùng con số phần trăm tuyệt đối (một trăm
phần trăm) ở bất kỳ slide nào — mọi phát biểu định lượng phải là `x/y`.

**Quy ước đếm.** Cùng một đại lượng có thể ra nhiều số tuỳ cách đếm (bài học
`AGENTS.md`: "63 bảng / 52 ID / 51 ID / 35 mục / 24 ID" của OTES). Vì vậy mỗi
bảng phải ghi **đếm theo cách nào**: ARTEMIS đếm theo **ca × lượt** trên **tất cả
jsonl** kể cả lượt lỗi môi trường; tỉ lệ flow đếm theo **danh sách `FLOWS`** (11
phần tử, dù `flows.py:1` ghi "10 ca").

---

## Slide 17 · Demo WF-01 — Mở dự án SRS cho nhóm sinh viên

**Tiêu đề:** Kịch bản demo WF-01 đi đúng 5 bước đặc tả W10, và ba lượt chạy thật
cho thấy đường hạnh phúc chạy được còn nhánh lỗi chặn đúng nhưng chưa báo được
lỗi cho người dùng.

**Thời lượng:** 60 giây.

- **Chuẩn bị (đo được, không phải giả định):** realme RMX3686 Android 14, cắm
  USB, app `com.example.srs_review_ai_mobile` bản **debug** nhánh
  `feat/docker-setup`; dữ liệu là **Firestore thật**, không phải fixture
  (`artemis-run-log.md:9-10, 61-63`).
- **5 bước bấm:** (1) Tổng quan đọc lời chào + 6 thẻ (TC01); (2) vào Lớp học, tìm
  "SE17" (FL03); (3) mở biểu mẫu tạo dự án UI-16, chọn nhóm thuộc đợt đang hoạt
  động (BR-01-01), nhập tên + ngày bắt đầu + hạn nộp (BR-01-03); (4) Lưu → hệ
  thống kiểm BR-01-01…04 rồi ghi `projects/{id}` + `_meta/snapshot` và xếp bản
  ghi vào outbox SQLite; (5) mở chi tiết dự án vừa tạo (TC05) và kiểm server đã
  nhận qua `POST /sync/push` (`workflow-spec.md:12`, `rtm.md:59-62`).
- **Nhánh lỗi phải diễn:** để trống tên → chặn lưu và hiện "Nhập tên và khoảng
  thời gian dự án hợp lệ." (BR-01-03, FL02).
- **Số đo hiện có (một lượt × mỗi flow):** FL01 **FAIL 900 s** (app ANR trên
  Xiaomi, bản debug); FL02 **FAIL 181 s** — chặn lưu đúng (14 → 14 dòng) nhưng
  `error_text: ""`, tức **không hiện lỗi**; FL03 **PASS 303 s**
  (`artemis-run-log.md:121-126`). Vì vậy kịch bản này **chưa có lượt xanh đầy
  đủ**: `[CHỜ DEMO]` một lượt WF-01 xanh trọn 5 bước.
- **Cách nói khi bảo vệ:** "Ba lượt chạy thật cho WF-01: một lượt xanh ở nhánh
  tìm lớp, hai lượt đỏ — một do ANR của bản debug, một do app chặn đúng nhưng
  không hiện thông báo. Chúng tôi không gọi đó là đã xong."

**Khối hình:** ảnh từng bước của ARTEMIS (Replay) ghép 3 khung: biểu mẫu tạo dự
án · thông báo chặn khi trống tên (khung đỏ, ghi "chưa hiện") · chi tiết dự án
sau khi lưu.

**Chân trang:** `workflow-spec.md:12` · `artemis-run-log.md:121-126` · `rtm.md:59-62`.

---

## Slide 18 · Demo WF-02 — Nộp SRS và duyệt có AI hỗ trợ

**Tiêu đề:** Kịch bản demo WF-02 chứng minh được chuỗi duyệt phía giảng viên và
luật chặn quyết định, nhưng chưa chứng minh được đường nộp của sinh viên lẫn
việc AI đọc chính tệp vừa nộp.

**Thời lượng:** 90 giây.

- **Bước 1 — SV nộp (UI-03):** chọn tệp, kiểm định dạng/rỗng/dung lượng ≤ 30 MB
  (BR-02-03…05), tải lên Cloudinary, ghi `submissions/{id}` + `srs_reports/{id}`,
  đẩy thông báo vào `users/{uid}/inbox` của GV (`workflow-spec.md:25`,
  `rtm.md:71`). **Trạng thái: `[CHỜ DEMO]`** — FL11 chưa chạy lượt nào
  (`plan 13` §0).
- **Bước 2 — GV nhận và mở yêu cầu:** thông báo đã kiểm bằng FL08 **PASS 293 s**
  (`artemis-run-log.md:130`); mở yêu cầu UI-21/22 chuyển `waiting` → `inReview`
  (BR-02-17, TC07, FL04).
- **Bước 3 — chạy Đánh giá AI:** `POST /review/batch`, giữ lỗi có trích dẫn khớp
  ≥ 0.92 (BR-02-13), 50 lượt/ngày/người (BR-02-14), client ngắt sau 90 s
  (BR-02-15) (`workflow-spec.md:25`, `rtm.md:73`).
- **Bước 4 — quyết định:** Yêu cầu sửa khi ghi chú trống bị chặn (FL05 **PASS
  868 s**); quyết định lưu kèm phản hồi (`artemis-run-log.md:127`).
- **Số đo hiện có:** FL04 **FAIL 213 s** — luồng đúng (điểm 78, số chờ 6 → 5)
  nhưng app ghi "Đã phê duyệt" trong khi kịch bản viết sai chữ "Đã duyệt", và
  **log FastAPI có 0 `POST /review`** → điểm 78 lấy từ đâu chưa rõ; FL06
  **FAIL 1200 s** (hết giờ, runner đã dừng task) (`artemis-run-log.md:126-128`).
- **Điều bắt buộc phải nói:** AI đang chấm **nội dung mẫu theo tên tài liệu**,
  không phải tệp PDF trên Cloudinary (`dom/review_policy.dart:52-57`,
  `p2-design.md:7`). Không được nói "AI chấm tệp sinh viên nộp".

**Khối hình:** 4 khung ảnh: Cloudinary/thông báo · hàng chờ UI-22 · panel Đánh
giá AI (điểm + trích dẫn) · thanh quyết định có lý do.

**Chân trang:** `workflow-spec.md:25` · `rtm.md:71-74` · `artemis-run-log.md:126-130`.

---

## Slide 19 · Bước cuối WF-02 — công bố quyết định cho sinh viên

**Tiêu đề:** Trạng thái cuối được lưu và khoá đúng như đặc tả, nhưng bước "công
bố cho sinh viên" chưa có bề mặt nào trong sản phẩm nên demo chỉ đi được tới
phía giảng viên.

**Thời lượng:** 45 giây.

- **Đã có:** `decideReview` ghi `supervisorStatus` ∈ {`approved`,
  `needsRevision`, `notAccepted`}; badge trạng thái ở UI-22; `audit` ghi vết;
  từ trạng thái cuối, mọi thao tác ghi bị chặn với thông điệp "Đánh giá đã hoàn
  tất; lịch sử được giữ nguyên." (BR-02-18, `rtm.md:75`).
- **Chưa có (phải nói thẳng):** không có màn hình sinh viên xem quyết định —
  vai `student` chỉ được dựng `StudentUploadScreen` (`auth_wrapper.dart:25-27`);
  không có push FCM cho SV khi GV quyết định — server chỉ có
  `/notifications/send` và `/notifications/submission`
  (`rtm.md:75`, `business-rules.md:66`).
- **Vì vậy kịch bản demo bước cuối:** (1) GV chốt "Đã phê duyệt" ở UI-22;
  (2) badge đổi trạng thái, số chờ trên Tổng quan giảm 1 (FL04, TC01 — BR-03-02);
  (3) mở lại yêu cầu → thao tác ghi bị chặn (BR-02-18, **chưa có TC**);
  (4) phía sinh viên: `[CHỜ DEMO]` — chưa có bề mặt để quay.
- **Rủi ro khi bị hỏi:** "Sinh viên biết kết quả bằng cách nào?" Trả lời trung
  thực: hiện chỉ thấy khi tự mở dự án trong app, và điều đó cũng chưa có màn
  hình riêng; đây là việc còn lại, không phải tính năng đã xong.

**Khối hình:** sơ đồ 2 cột "Đã có (GV)" | "Chưa có (SV)", cột phải để khung
vàng `[CHỜ DEMO]` thay vì ảnh giả.

**Chân trang:** `rtm.md:75` · `auth_wrapper.dart:25-27` · `business-rules.md:44, 66`.

---

## Slide 20 · Video dự phòng và cách chạy lại

**Tiêu đề:** Đường quay dự phòng đã có script tự động, và điều kiện để nó ra
được một video đúng là một lượt chạy xanh — thứ hiện chưa có.

**Thời lượng:** 30 giây.

- **Ba script đã có trong repo:** `e2e_test/full_run.sh` (quay UI Artemis
  headless + quay điện thoại bằng `scrcpy` + chạy flow), `e2e_test/compose_videos.py`
  (ghép trái/phải, căn giờ theo `sessions.start_time`), `e2e_test/record_artemis_ui.mjs`
  (ghi trang Workspace) (`full_run.sh:1-3`, `compose_videos.py:1-13`).
- **Điều kiện chạy:** Artemis UI ở `:8020`, server Docker ở `:8000`, điện thoại
  cắm USB đã mở khoá, `adb reverse tcp:8010 tcp:8000` (`full_run.sh:9-24`).
- **Vì sao chưa có video:** lượt chạy 06/11 không có video replay vì `scrcpy`
  chưa cài (`artemis-run-log.md:38-40`); các lượt sau dừng giữa chừng vì hết
  giờ hoặc rớt USB (`artemis-run-log.md:106-117`). Video demo: `[CHỜ DEMO]`.
- **Dự phòng nếu video hỏng tại buổi bảo vệ:** dùng ảnh từng bước trong Replay
  của ARTEMIS (mỗi bước có ảnh, không cần `scrcpy`) — đã có sẵn cho các lượt
  `completed`.
- **Checklist trước giờ G:** (1) `--profile`/`--release` thay bản debug để loại
  ANR (`artemis-run-log.md:112-115`); (2) gọi `POST /api/stop` cho mọi session
  `running` — ARTEMIS để task mồ côi chạy 25 phút và chặn hàng đợi
  (`artemis-run-log.md:90-91`); (3) kiểm `max_upload_file_size_mb = 30` trên
  màn hình (TC10); (4) chạy `--runs 3` cho mỗi WF.

**Khối hình:** ba khung: `full_run.sh` · ảnh chụp cặp video trái/phải · checklist
4 dòng.

**Chân trang:** `full_run.sh:1-24` · `compose_videos.py:1-13` · `artemis-run-log.md:38-40, 90-91, 106-117`.

---

## Slide 21 · Số đo kiểm thử — bảng ARTEMIS, tách lỗi môi trường

**Tiêu đề:** Bảng đo thật cho thấy tầng chức năng đã ổn định (TC01 9/9, TC04 3/3,
TC05 3/3) trong khi tầng luồng còn đỏ ở 5/8 flow, và phần lớn cái đỏ là lỗi môi
trường chứ không phải lỗi app.

**Thời lượng:** 90 giây.

### 21.1 Bảng ARTEMIS — đếm theo ca × lượt, trên **tất cả** jsonl

| Ca | Đạt / Lượt | Ca | Đạt / Lượt |
|---|---|---|---|
| TC01 Tổng quan | **9/9** | FL01 Tạo dự án | **1/3** |
| TC02 Môn học | **5/9** | FL02 Dự án trống tên | **1/3** |
| TC03 Tìm "SE17" | **4/6** | FL03 Lớp học | **2/2** |
| TC04 Tìm rỗng | **3/3** | FL04 AI + duyệt | **0/1** |
| TC05 Chi tiết dự án | **3/3** | FL05 Yêu cầu sửa trống | **1/2** |
| | | FL06 AI quá 90 s | **0/1** |
| | | FL07 Lịch sử | **0/1** |
| | | FL08 Thông báo | **1/1** |
| | | FL09, FL10, FL11 | **chưa chạy lượt nào** |

Nguồn: `plan 13` §0 (`docs/plans/13-defense-slides-roadmap-2026-11-10.md:16`).

### 21.2 Ba nhóm phải tách, không được cộng gộp

| Nhóm | Gồm những gì | Cách xử lý khi báo cáo |
|---|---|---|
| **A. Lỗi app thật** | FL02: chặn lưu đúng nhưng `error_text: ""` (`artemis-run-log.md:124`) · FL04: ghi sai nhãn + **0 `POST /review`** trong log FastAPI (`:126`) · lệch số 3 môn/7 lớp với 4 môn/8 lớp (`:81-82`) | Tính là đỏ, ghi nguyên nhân |
| **B. Lỗi môi trường** | 4 lượt Xiaomi rớt adb (2 `TaskTimeoutError` + 2 `TaskRejectedError: device not connected`) — **không tính vào tỉ lệ** (`:76-77`) · ANR trên Xiaomi với bản debug ~200 MB, chưa thử `--profile`/`--release` (`:112-115`) · `Accessibility helper unavailable`, `scrcpy` chưa cài (`:38-40`) | Nêu riêng, không tính là app sai |
| **C. Hết giờ — chưa kết luận** | FL01 900 s, FL06 1200 s, FL07 900 s: hết giờ, **chưa cho biết app đúng hay sai** (`:128-129, 132-133`) | Ghi "chưa kết luận", không ghi FAIL của app |

### 21.3 Các tầng kiểm thử khác

| Tầng | Số đo | Nguồn |
|---|---|---|
| Test case thiết kế cho Mobile | **92 TC** | `plan 13` §0 → `docs/testing/test-cases-mobile.md` |
| Unit + widget Mobile (một lượt) | **185/185 pass** | `plan 13` §0 → `mobile/docs/evidence/final-audit/ui-flow-audit.md:58` |
| Pytest server | **`[CẦN SỐ]`** — plan 13 chỉ ghi "pytest server", chưa có con số | `plan 13` §0 |
| Guardrail tĩnh | **9 nhóm luật** (`tools/check_guardrails.py`) | `AGENTS.md:41` |
| Tỉ lệ flow PASS | **~6/14** (đếm theo danh sách `FLOWS` 11 phần tử + 3 ca chưa chạy) | `p2-design.md:122`, `rtm.md:224-226` |

**Bài học đo lường phải nói trên slide:** ARTEMIS báo `completed/succeeded=True`
mà `result.output = null` ở 2/3 lượt đầu — nếu test chỉ assert `succeeded` thì
cả hai lượt "xanh" mà không kiểm được gì (`artemis-run-log.md:27-37`).

**Khối hình:** bảng 21.1 ở giữa; hai cột 21.2 hai bên; dòng 21.3 dưới cùng.

**Chân trang:** `artemis-run-log.md:76-77, 121-133` · `plan 13:15-16` · `AGENTS.md:41`.

---

## Slide 22 · Achievements — những gì đã chứng minh được

**Tiêu đề:** Đồ án đã chứng minh được tính khả thi của kiến trúc và độ phủ đặc
tả, chứ không chỉ là demo giao diện: hai workflow đạt 5/5 câu W05, 27 luật nghiệp
vụ có `file:dòng`, và tầng chức năng chạy ổn định trên thiết bị thật.

**Thời lượng:** 45 giây.

- **Đặc tả đạt chuẩn W05:** WF-01 **5/5**, WF-02 **5/5**; WF-03 3/5 và đã gộp
  vào bước cuối WF-02 (`workflow-spec.md:44-60`).
- **Luật nghiệp vụ truy vết được:** **27 luật** BR-01/02/03, mỗi luật có
  `file:dòng` và thông điệp chép nguyên văn từ code (`p2-design.md:44`,
  `business-rules.md:13-54`).
- **Truy vết xuyên 7 tầng:** WF → bước → BR → UI-xx → class/`file:dòng` → entity
  → case, kèm danh sách ô `chưa có` có cách kiểm lại (`rtm.md:1-11, 88-101`).
- **Bề mặt sản phẩm:** **37 màn** (Mobile **27** UI-01…UI-27 + Admin Web **10**
  UI-28…UI-37) (`p2-design.md:55, 57`).
- **Kiểm thử:** **92 TC** thiết kế, **185/185** unit + widget pass, **9 nhóm
  guardrail** tĩnh (`plan 13` §0, `AGENTS.md:41`).
- **Chạy thật trên máy thật:** TC01 **9/9**, TC04 **3/3**, TC05 **3/3**; lượt
  probe đầu **3/3 PASS**, trung bình **30,1 s** (`plan 13` §0,
  `artemis-run-log.md:47-53`).
- **Cơ chế offline outbox có test và có số:** `POST /sync/push` → `sync_records`,
  kiểm bằng FL09/TC12 (dù ca đó tạo **học kỳ**, không tạo dự án — `rtm.md:207-214`).
- **Kỷ luật số đo:** mọi bảng ghi cách đếm; lỗi môi trường tách khỏi lỗi app
  (`plan 13` §0, slide 21).

**Khối hình:** 6 thẻ số (27 · 37 · 92 · 185/185 · 9 · 5/5) — mỗi thẻ một dòng
nguồn.

**Chân trang:** `workflow-spec.md:44-60` · `p2-design.md:44, 55-57` · `plan 13:15-16` · `AGENTS.md:41`.

---

## Slide 23 · Limitations — những gì chưa xong, nói thẳng

**Tiêu đề:** Sáu khoảng trống dưới đây là giới hạn thật của bản nộp, và mỗi cái
đều có `file:dòng` chứng minh — không có cái nào là "chắc là chạy được".

**Thời lượng:** 60 giây.

| # | Hạn chế | Bằng chứng |
|---|---|---|
| ✓ | **Đã vá — bài nộp vào hàng chờ:** GV bấm "Đưa vào hàng chờ duyệt" → `queueSubmission` tạo yêu cầu `waiting` (tay, không tự động) | `fe/review_actions.dart:127`, `student_submissions_card.dart:148` |
| ✓ | **Đã vá — AI đọc tệp nộp:** `POST /documents/extract` lấy text PDF/DOCX/MD từ Cloudinary; seed vẫn dùng mẫu | `server/app/api/documents.py:164`, `fe/review_actions.dart:552-556` |
| 1 | **Không chặn nộp trễ.** Không có luật hạn nộp cứng: nộp sau `deadline` không bị chặn | `business-rules.md:60`, `p2-design.md:49` |
| ✓ | **Đã vá — push cho SV:** `decideReview` → `POST /notifications/decision` | `fe/review_actions.dart:423`, `server/app/api/notifications.py:386` |
| ✓ | **Đã vá — test 9 luật:** `business_rules_coverage_test.dart` (11 ca) + `test_br_rate_limit.py` (ca thứ 51 → 429), xanh: pytest 436 pass, flutter +335 | `docs/workflow/br-test-coverage.md` |
| 2 | **FL11–FL14 viết xong, chưa chạy** — cần `e2e_test/full_run.sh` | `e2e_test/flows.py:442-464` |
| 3 | **Chưa deploy VPS** — hai endpoint mới chỉ có ở local | `server/app/api/documents.py`, `notifications.py:386` |
| 4 | **PDF scan chưa OCR** — tệp chỉ có ảnh trả 422 | `server/app/infrastructure/document_text.py:10-12` |
| 5 | **5 luật chỉ có unit/pytest, không E2E:** BR-02-03/04/06/07/14 | `br-test-coverage.md` |

**Năm hạn chế kỹ thuật nói thêm nếu bị hỏi:**

- **Rate limit 50 lượt/ngày nằm trong RAM** — restart server là reset
  (`p2-design.md:36`, `rtm.md:73`).
- **14 bảng Postgres của schema đích chưa được route API nào đọc/ghi** — mới có
  trong Alembic (`p2-design.md:103`).
- **Firestore rules cho collection học vụ là `allow read, write: if signedIn();`**
  — không kiểm kiểu dữ liệu hay quyền sở hữu (CR-01, `p2-design.md:104`).
- **38 file `.dart` cũ** còn trong `mobile/lib/screens/`, 1 màn demo, 3 tab
  admin không có route (`p2-design.md:60`).
- **AI bị loại lỗi theo BR-02-13 không báo cho người dùng**, chỉ đếm vào
  `dropped_issue_count` (`business-rules.md:59`).

**Khối hình:** bảng 6 hàng, tô vàng cột "Bằng chứng" như nhãn `chưa có`.

**Chân trang:** `business-rules.md:44, 59-66` · `rtm.md:99, 133-142` · `p2-design.md:5, 7, 36, 49, 103-104, 115`.

---

## Slide 24 · Conclusion — kết luận và việc tiếp theo

**Tiêu đề:** Đồ án đã trả lời được câu hỏi "quy trình duyệt SRS thủ công có thể
được thay bằng một luồng có trạng thái, có luật và có AI hỗ trợ hay không", và
cái còn thiếu là ba mối nối cụ thể chứ không phải ý tưởng.

**Thời lượng:** 45 giây.

- **Đã trả lời:** hai workflow lõi đạt 5/5 câu W05; 27 luật nghiệp vụ có
  `file:dòng`; kiến trúc Mobile + Admin Web + FastAPI + Firebase/Cloudinary chạy
  thật trên thiết bị (TC01 9/9, TC04 3/3, TC05 3/3) (`workflow-spec.md:44-60`,
  `p2-design.md:44`, `plan 13` §0).
- **Chưa trả lời:** liệu AI có chấm đúng **tệp sinh viên nộp** hay không — hiện
  nó chấm nội dung mẫu (`dom/review_policy.dart:52-57`); và liệu sinh viên có
  nhận được quyết định hay không — hiện chưa có bề mặt lẫn push
  (`rtm.md:75`).
- **Ba việc tiếp theo, theo thứ tự đúng:**
  1. Nối `submit` → tạo yêu cầu `waiting` trong `reviewState.requests` (mối nối
     B1 → B2 của WF-02);
  2. Trích văn bản từ tệp nộp và đưa vào `ReviewPolicy.aiUnits` thay cho
     `documentSamples`;
  3. Thêm màn hình + push cho sinh viên ở bước cuối WF-02, kèm TC cho BR-02-18
     và 8 BR còn thiếu case.
- **Điều đồ án này cố ý không làm:** không nâng trần 40 requirement/lượt lên 63,
  vì quota server là 50 request/ngày và cần 10 request dự phòng (`AGENTS.md:48`);
  không đưa Desktop vào trục chính — engine chấm F1–F9 chỉ ở phụ lục A5
  (`plan 13:49`).
- **Một câu để đóng:** "Chúng tôi không nộp một demo đã được trang điểm; chúng
  tôi nộp một hệ thống có bảng đo, có chỗ đứt được chỉ tên, và có đường sửa."

**Khối hình:** ba cột "Đã trả lời / Chưa trả lời / Việc tiếp theo"; cuối slide là
dải 3 bước 1 → 2 → 3.

**Chân trang:** `workflow-spec.md:44-60` · `dom/review_policy.dart:52-57` · `rtm.md:75, 133-142` · `AGENTS.md:48`.

---

# Phụ lục

## A1 · Ma trận 27 luật nghiệp vụ → case E2E

**Tiêu đề:** Mỗi luật trong 27 luật đều có `file:dòng`, và 8 luật trong đó chưa
có case E2E nào đi qua.

Nguồn: `business-rules.md:13-54` (cột "Case E2E"), `rtm.md:133-142` (danh sách 8
luật thiếu case). Ô vàng = `chưa có` case.

**WF-01 — Mở dự án (8 luật)**

| Mã | Case | Mã | Case |
|---|---|---|---|
| BR-01-01 | FL01 | BR-01-05 | `chưa có` |
| BR-01-02 | **`chưa có`** | BR-01-06 | `chưa có` |
| BR-01-03 | FL02 | BR-01-07 | `chưa có` |
| BR-01-04 | **`chưa có`** | BR-01-08 | `chưa có` |

**WF-02 — Nộp và duyệt SRS (17 luật; BR-02-12 đã bỏ)**

| Mã | Case | Mã | Case | Mã | Case |
|---|---|---|---|---|---|
| BR-02-01 | FL11 | BR-02-07 | **`chưa có`** | BR-02-13 | FL04 |
| BR-02-02 | FL11 | BR-02-08 | FL04 | BR-02-14 | **`chưa có`** |
| BR-02-03 | **`chưa có`** | BR-02-09 | FL05 | BR-02-15 | FL06 |
| BR-02-04 | **`chưa có`** | BR-02-10 | FL05 | BR-02-16 | FL04, FL05 |
| BR-02-05 | TC10 | BR-02-11 | `chưa có` | BR-02-17 | FL04 |
| BR-02-06 | **`chưa có`** | BR-02-12 | bỏ (xem `rtm.md:175-183`) | BR-02-18 | **`chưa có`** |

**WF-03 — Theo dõi kết quả (2 luật):** BR-03-01 → FL10 · BR-03-02 → FL04, FL07.

**Đọc bảng này cho đúng:** cột Case chép nguyên văn từ `business-rules.md`.
`rtm.md` §6.2 nêu **đích danh 8 luật** cần viết case (BR-01-02, BR-01-04,
BR-02-03, BR-02-04, BR-02-06, BR-02-07, BR-02-14, BR-02-18) — 8 là **danh sách
rtm chọn**, không phải tổng số ô trống: bảng gốc còn 5 ô `—` khác (BR-01-05,
BR-01-06, BR-01-07, BR-01-08, BR-02-11) chưa được xếp vào danh sách đó.

**Chân trang:** `business-rules.md:13-54` · `rtm.md:88-101, 133-142`.

---

## A2 · Bản đồ 37 màn hình (UI-01…UI-37)

**Tiêu đề:** 37 màn đang chạy, nhưng 7 màn thiếu trạng thái chuẩn và vai sinh
viên chỉ có đúng một màn.

Nguồn: `p2-design.md:55-62`, `ui-map.md` §3–§6.

| Nhóm | Số màn | Ghi chú |
|---|---|---|
| Mobile — Giảng viên (WF-01) | UI-14…UI-18 | nhóm/lớp/dự án + biểu mẫu bottom sheet |
| Mobile — Giảng viên (WF-02) | UI-01, UI-03, UI-19…UI-23 | nộp bài, hàng chờ, đọc kết quả, thanh quyết định |
| Mobile — bước cuối + theo dõi | UI-02, UI-05, UI-24…UI-26 | Tổng quan, hộp thư, lịch sử phiên bản/đánh giá |
| Mobile — nền & vận hành | 18 màn còn lại | danh mục học vụ, tìm kiếm, cài đặt |
| Admin Web | UI-28…UI-37 | cổng xác thực + 6 tab |
| Sinh viên | **UI-03** | chỉ màn nộp bài (`auth_wrapper.dart:25-27`) |

**7 màn thiếu trạng thái Empty/Loading/Error:** UI-03 (thiếu Empty), UI-24
(thiếu `AppEmptyState`), UI-27 (thiếu Loading + Error), UI-32, UI-33, UI-34,
UI-35 (thiếu Empty) — `p2-design.md:59`.

**Nợ kỹ thuật đếm được:** 38 file `.dart` cũ trong `mobile/lib/screens/`,
1 màn demo, 3 tab admin không có route (`p2-design.md:60`).

**Chân trang:** `p2-design.md:55-62` · `ui-map.md:51-53` · `auth_wrapper.dart:25-27`.

---

## A3 · Schema: runtime đang chạy vs schema đích

**Tiêu đề:** Hệ thống đang chạy trên hai runtime (Firestore + SQLite) với 5
trạng thái, trong khi schema đích 14 bảng Postgres với 4 trạng thái chưa được
nối vào API nào.

Nguồn: `p2-design.md:99-106`, `physical-schema.md` §2–§3, `rtm.md:185-196`.

| Tầng | Có gì | Chưa có gì |
|---|---|---|
| **Firestore** | `users/{uid}` + `inbox`, `admins/{uid}`, 9 collection học vụ (courses, classes, groups, projects, registrations, semesters, offerings, ruleSets, students), `submissions`, `srs_reports`, `crash_logs`, `analytics_events` | **không có** `documents/{id}` — tài liệu nằm trong `_meta/snapshot` |
| **SQLite Mobile** | `srs_academic.db`: `academic_snapshot`, `outbox` (+2 index), `sync_meta` | — |
| **SQLite Server** | 7 bảng: `cache_entries`, `cache_meta`, `sync_records`, `sync_ops`, `sync_counter`, `criteria`, `rubric_overrides` | — |
| **Postgres (đích)** | 14 bảng trong `models.py`, có trong Alembic `0001_*`, `0002_*` | **chưa route API nào đọc/ghi** |

**Hai bộ trạng thái lệch nhau:** runtime `supervisorStatus` ∈ {waiting, inReview,
approved, needsRevision, notAccepted} (**5**); schema đích `submissions.status` ∈
{submitted, reviewed, approved, changes_requested} (**4**) và
`teacher_decisions.decision` chỉ {approved, changes_requested}
(`p2-design.md:104`).

**Chân trang:** `p2-design.md:99-106` · `physical-schema.md` §2–§3 · `rtm.md:185-196`.

---

## A4 · Runbook chạy demo (dùng khi tập trước giờ bảo vệ)

**Tiêu đề:** Toàn bộ lượt demo chạy được bằng ba lệnh, với bốn điều kiện môi
trường phải kiểm trước.

| Bước | Lệnh / việc | Kiểm gì |
|---|---|---|
| 0 | `adb devices` + mở khoá máy | thiết bị phải hiện trong danh sách; máy rớt adb là nguyên nhân của 4 lượt FAIL đã đo (`artemis-run-log.md:76-77`) |
| 1 | `e2e_test/full_run.sh FL01,FL02,...` | quay UI + điện thoại song song rồi chạy flow (`full_run.sh:1-3`) |
| 2 | `python3 e2e_test/compose_videos.py <ui.webm> --phone phone.mkv` | ghép video, căn giờ theo `sessions.start_time` (`compose_videos.py:1-13`) |
| 3 | mở `http://localhost:8020` → Replay | đọc ảnh từng bước khi video hỏng |

**Bốn điều kiện:** Artemis UI `:8020`; server Docker `:8000` (+ `docker logs -f`
để bắt `POST /review` — thiếu log này thì FL04 lại "điểm 78 không rõ nguồn");
điện thoại đã `adb reverse tcp:8010 tcp:8000`; **stop mọi task `running`** trước
khi chạy lượt mới.

**Dữ liệu chuẩn bị:** tài khoản GV (Firestore thật, không phải fixture), một lớp
có nhóm chưa có dự án (để không vướng BR-01-02), một yêu cầu ở `waiting`, và
`max_upload_file_size_mb = 30` (TC10).

**Chân trang:** `full_run.sh:1-24` · `compose_videos.py:1-13` · `artemis-run-log.md:76-77, 90-91`.

---

## A5 · Desktop — engine chấm (ngoài trục chính)

**Tiêu đề:** Desktop không phải trục của đồ án nhưng là nơi luật chấm được cài
thật, nên nó ở phụ lục chứ không bị bỏ.

Nguồn: `AGENTS.md:10, 16-18, 21, 48`; `plan 13:49`; `p2-design.md:51`.

- **Vai trò:** `desktop/` là Flutter desktop (Dart SDK `^3.12.2`, package
  `srs_review_ai`), lo **UI + tách requirement**; phần chấm có engine
  deterministic **F1–F9** chạy offline, không tốn quota (`AGENTS.md:10`,
  `plan 13:49`).
- **F7/F8/F9 là check syllabus** lấy nguyên văn từ đề SEP490; F7 đo use case,
  F9 đo kích thước use case (`desktop/lib/deterministic_checks/checks/syllabus_checks.dart:1, 48, 74`).
- **Luật chấm sống ở `review-rules/`, không ở prompt:** `RULEBOOK.md` là nguồn
  sự thật; muốn port một luật vào app phải tra
  `review-rules/adapters/app-port-map.md` xem đã có `CheckId`/`DiagramType`
  chưa (`AGENTS.md:16, 23`).
- **Bằng chứng hiệu chuẩn thang điểm:** ledger chạy thật trên **3 tài liệu có
  sẵn** — OTES, HisWise, CarbonX — trong `reviews/` (`AGENTS.md:18`).
- **Kết luận đã đo của engine v2:** 4 lần chạy thật cho thấy **8 check giá trị
  nhất đều thuần text**, đơn vị output của app sai, và cần workflow hai pass
  (`AGENTS.md:21` → `docs/plans/7-review-engine-v2-2026-09-15.md`).
- **Hai con số dùng được:** trần **40 requirement/lượt chấm** (kẹp, không từ
  chối) và trần tệp **30 MB** phía client (`AGENTS.md:48-49`).
- **Không được nói:** Desktop chưa có mặt trong buổi demo này; mọi con số về
  chất lượng chấm của Desktop (độ chính xác, thời gian) **chưa đo trong lượt
  này** → `[CẦN SỐ]` nếu bị hỏi.

**Chân trang:** `AGENTS.md:10, 16-18, 21, 48-49` · `plan 13:49` · `p2-design.md:51`.

---

## A6 · Checklist G5 và câu hỏi phản biện dự kiến

**Tiêu đề:** Tám ô bằng chứng của G5 đều trỏ được về file cụ thể, và năm câu
phản biện dễ bị hỏi nhất đều có câu trả lời kèm `file:dòng`.

**G5 — tám ô bằng chứng**

| Ô | Bằng chứng | Trạng thái |
|---|---|---|
| Vấn đề & phạm vi | `p1-problem.md` slide 01–04 | có |
| Workflow + đặc tả | `workflow-spec.md` (WF-01, WF-02 đạt 5/5) | có |
| Luật nghiệp vụ | `business-rules.md` (27 luật, `file:dòng`) | có |
| Sơ đồ | `docs/uml/` (activity, state, architecture, sequence, ERD) | có, **thiếu class diagram** (`[CHỜ SƠ ĐỒ]` ở slide 13) |
| UI & sitemap | `ui-map.md`, `p2-design.md:55-62` | có, thiếu màn SV xem quyết định |
| Truy vết | `rtm.md` | có, còn 8 BR thiếu case |
| Kiểm thử | `plan 13` §0, `artemis-run-log.md`, `test-cases-mobile.md` | có, còn 3 lượt hết giờ |
| Demo + video | `e2e_test/full_run.sh`, `compose_videos.py` | script có, **video `[CHỜ DEMO]`** |

**Năm câu phản biện dự kiến**

1. *"AI chấm tệp sinh viên nộp à?"* — Có, với yêu cầu tạo từ bài nộp: server
   trích text tệp Cloudinary (`server/app/api/documents.py:164`); yêu cầu seed vẫn
   dùng nội dung mẫu. PDF scan chưa OCR.
2. *"Sinh viên nộp xong thì giảng viên thấy trong hàng chờ chứ?"* — Thấy trong
   thẻ bài nộp; GV bấm "Đưa vào hàng chờ duyệt" để tạo yêu cầu `waiting`
   (`fe/review_actions.dart:127`). Chưa tự động.
3. *"Nộp trễ thì sao?"* — Không chặn; chưa có luật hạn nộp cứng
   (`business-rules.md:60`).
4. *"AI bịa trích dẫn thì sao?"* — Lỗi có trích dẫn khớp < 0.92 bị loại và đếm
   vào `dropped_issue_count` (BR-02-13); nhưng bị loại **không báo cho người
   dùng** (`business-rules.md:59`).
5. *"Sao biết test xanh là thật?"* — Vì ARTEMIS từng báo `succeeded=True` mà
   `output = null`; test đọc giá trị từ báo cáo trong DB chứ không tin cờ trạng
   thái (`artemis-run-log.md:27-37`).

**Chân trang:** `plan 13:187-191` · `workflow-spec.md:44-73` · `rtm.md:88-142`.

---

## Danh sách ô còn chờ (để điền trước khi chốt deck)

| Slide | Ô | Cần gì |
|---|---|---|
| 17 | `[CHỜ DEMO]` | một lượt WF-01 xanh trọn 5 bước |
| 18 | `[CHỜ DEMO]` | lượt FL11 (SV nộp) + một lượt FL04 có `POST /review` trong log |
| 19 | `[CHỜ DEMO]` | bề mặt phía SV ở bước cuối WF-02 (chưa có màn hình) |
| 20 | `[CHỜ DEMO]` | video mp4 ghép từ `full_run.sh` + `compose_videos.py` |
| 21 | `[CẦN SỐ]` | số pytest server (plan 13 chỉ ghi "pytest server") |
| 22 | — | (đủ số, không còn ô chờ) |
| 23 | — | (đủ bằng chứng) |
| 24 | — | (đủ) |
| A5 | `[CẦN SỐ]` | số đo chất lượng chấm của Desktop engine (nếu bị hỏi) |
| 13 | `[CHỜ SƠ ĐỒ]` | class diagram `docs/uml/seqclass/*class*.png` |
