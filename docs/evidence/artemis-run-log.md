# Nhật ký chạy ARTEMIS — Lab 3 §7

Mỗi lượt chạy ARTEMIS được ghi vào đây theo thứ tự thời gian. Ghi cả lượt hỏng, kèm lý do.

## Môi trường

| Mục | Giá trị |
|---|---|
| Máy thật | realme RMX3686, Android 14, serial `UGKFPBYDTGE67HGY`, cắm USB |
| App | `com.example.srs_review_ai_mobile` (debug, nhánh `feat/docker-setup`) |
| ARTEMIS | `/Volumes/SSD/AppData/artemis`, commit `351ca84` |
| Daemon + Web UI | `artemis ui --port 8020` → http://localhost:8020 (cổng 8000 bị `python -m http.server` khác giữ) |
| Model | qua 9router: `gemini/gemini-3.6-flash` (fallback `gemini-3.5-flash-lite`), profile `flash` |
| Client | `artemis_client.ArtemisClient` (package trong repo ARTEMIS), gọi từ Claude Code |
| Lịch sử gốc | `traces/data_engine.db` (bảng `sessions`, `steps`) + thư mục `traces/web_<ts>_<id>_PASS_<time>/` |

Cách xem lại một lượt: mở Web UI, vào mục Task Queue / Replay rồi chọn theo trace ID. Hoặc truy vấn thẳng DB:
`sqlite3 traces/data_engine.db "select step_number, action_taken from steps where session_id='<trace_id>'"`.

## 06/11/2026 — Thử ArtemisClient lần đầu (`e2e_test/try_artemis.py`)

Mục tiêu: mở tab Tổng quan, đọc tên người dùng và 6 thẻ thống kê, không bấm gì khác.
Giá trị trên màn hình lúc chạy: `Nguyễn Văn An`, `3 / 6 / 8 / 3 / 0 / 10`.

| # | Trace ID | ARTEMIS status | Thời gian | Giá trị quan sát được | Kết luận của test |
|---|---|---|---|---|---|
| 1 | `cde49b99-8ef8-4855-8a4b-d9c36fe0fad7` | completed | 50.2 s | `result.output = null` | **FAIL**: SUCCESS nhưng không có giá trị để kiểm |
| 2 | `3c7dda88-3c3d-47ba-9d8b-06d8c5422c89` | completed | 38.3 s | `result.output = null` (đã bật `enable_outputter=True`) | **FAIL**: như lượt 1 |
| 3 | `6357e660-c51d-4305-9eec-e1d2fc59d398` | completed | 22.7 s | `{"user":"Nguyễn Văn An","courses":3,"classes":6,"docs_waiting":8,"docs_reviewing":3,"registrations_waiting":0,"projects_to_handle":10}` | **PASS**: 4/4 check, khớp màn hình |

Thời gian lấy từ `end_time - start_time` của bảng `sessions`.

### Phát hiện

1. **ARTEMIS báo SUCCESS không đủ để kết luận.** Lượt 1 và 2 đều `completed / succeeded=True`, nhưng `result.output` là `null`. Nếu test chỉ assert `succeeded` thì cả hai lượt đều "xanh" mà không kiểm được gì. Đây đúng là lỗi mà đề yêu cầu tránh.
2. **Nguyên nhân `output = null`:** ở commit `351ca84`, `artemis/agents/outputter/outputter.py` có code nhưng không runner nào gọi tới. Đã grep: ngoài phần config và SDK không có chỗ nào dùng nó. Bật `enable_outputter=True` cũng không giúp gì (lượt 2).
3. **Cách kiểm giá trị đang dùng:** goal yêu cầu agent ghi JSON vào `explanation` của `report_task_status`. Test đọc báo cáo đó từ `traces/data_engine.db` (chế độ chỉ đọc) rồi assert từng trường. Agent thật sự đọc được giá trị: lượt 1–2 có đủ số liệu trong `explanation` dưới dạng văn bản, chỉ là không đi qua trường `output`.
4. **Cảnh báo môi trường, không làm hỏng lượt chạy:**
   - `Accessibility helper unavailable`: máy realme từ chối bật dịch vụ trợ năng qua adb, nên ARTEMIS dùng `uiautomator` để đọc cây UI.
   - `scrcpy` chưa cài, nên lượt chạy **không có video replay**; Web UI vẫn có ảnh từng bước. Muốn có video thì cài bằng `brew install scrcpy`.

## 06/11/2026 — Đổi model chính sang CMC DeepSeek (`cmc/deepseek/deepseek-v4-flash`)

Cấu hình: trong `config/artemis.jsonc`, `default.model` = `cmc/deepseek/deepseek-v4-flash` (provider Command Code của 9router, alias `cmc`); fallback = `gemini/gemini-3.6-flash`. Object Detector và Hopper giữ nguyên như trước. Bản cấu hình Gemini cũ được lưu ở `config/artemis.jsonc.gemini-20261106`.
Script giữ nguyên `e2e_test/try_artemis.py`.

| # | Trace ID | Status | Thời gian | Model thực sự trả lời | Giá trị quan sát được | Test |
|---|---|---|---|---|---|---|
| 1 | `f4bbdb92-fda9-4a8a-84e7-4b7dcf1b70c8` | completed | 35.9 s | `cmc/deepseek/deepseek-v4-flash`: 2 call, 191 164 prompt token | Nguyễn Văn An, 3/6/8/3/0/10 | **PASS** 4/4 |
| 2 | `42922f76-fe3b-45b5-b7a7-a3db3b795b4e` | completed | 26.6 s | như trên: 1 call, 69 257 token | Nguyễn Văn An, 3/6/8/3/0/10 | **PASS** 4/4 |
| 3 | `35f96f72-4ef7-4cb1-b586-2eed83e0bcd2` | completed | 27.8 s | như trên: 1 call, 119 858 token | Nguyễn Văn An, 3/6/8/3/0/10 | **PASS** 4/4 |

Tỷ lệ đạt: **3/3**. Thời gian trung bình: **30.1 s**. Không lượt nào phải rơi về fallback Gemini. Số liệu lấy từ dòng `LLM usage` trong `traces/<id>/stdout.log`.

So với Gemini (`gemini-3.6-flash`) trên cùng nhiệm vụ: lượt Gemini dùng định dạng JSON (lượt 3 ở trên) mất 22.7 s và ~10 000 prompt token cho mỗi call. DeepSeek chậm hơn khoảng 30% và tốn gấp 7–19 lần prompt token cho mỗi lượt, nhưng đọc đúng toàn bộ giá trị.

**Chưa kiểm chứng: DeepSeek có thật sự "nhìn" ảnh hay không.** App Flutter đưa toàn bộ chữ ra cây UI (`uiautomator`), nên nhiệm vụ này làm đúng được kể cả khi model chỉ đọc chữ. Muốn chứng minh model đọc ảnh, cần một ca mà đáp án chỉ có trong hình (ví dụ màu của biểu đồ, icon không có nhãn).

## 06/11/2026 — Bộ 12 ca theo chức năng (`e2e_test/run_suite.py --suite functions`)

Đổi máy giữa chừng: Xiaomi M2101K7BG (`49BEF6B6TCRSJNQW`, Android 13) rồi realme RMX3686. Tài khoản
Google đã đăng nhập: Le Huy Tuong. Dữ liệu là **Firestore thật**, không phải fixture (fixture ghi
"Nguyễn Văn An"), nên kỳ vọng được hiệu chuẩn lại bằng `uiautomator dump` trên máy, xem `e2e_test/cases.py`.
Model: DeepSeek. Mọi lượt ghi trong `e2e_test/results/2026-11-06.jsonl`.

| Ca | Máy | Lượt | Đạt | Ghi chú |
|---|---|---|---|---|
| TC01 Tổng quan | Xiaomi | 3 | 3 | `9e8b6cd9`, `34cdb145`, `c5a03661` |
| TC01 Tổng quan | realme | 6 | 6 | 2 vòng: `9bee20bc` `9186f556` `7bb080ec` / `0dc72c2a` `3f44a207` `02b29bb8` |
| TC02 Môn học | realme | 6 | 5 | `4a4c4183` FAIL: agent báo `count=2` (chỉ đọc 2 môn đang hiện, **không cuộn**) → lỗi của agent, app đúng 4 môn |
| TC03 Tìm 'SE17' | realme | 5 | 4 | `5f3f0adc` hết 600 s; lượt PASS chậm (117–496 s) |
| TC04 Tìm rỗng | realme | 3 | 3 | `2fafb943`, `f934eb1d`, `a5ed72e2` |
| TC05 Chi tiết dự án | realme | 3 | 3 | `755c2a05`, `2a6cd0ac`, `2300434c` |
| TC06–TC12 | — | 0 | — | Dừng theo yêu cầu, chuyển sang bộ flow |

Không tính vào tỉ lệ: 4 lượt trên Xiaomi FAIL vì **máy rớt adb** (2 lượt `TaskTimeoutError` + 2 lượt
`TaskRejectedError: device not connected`), đây là lỗi môi trường, không phải lỗi app.

### Phát hiện

1. **Số liệu không nhất quán giữa hai màn**: thẻ Tổng quan ghi `Môn học quản lý: 3`, `Lớp đang theo dõi: 7`;
   tab Tài khoản và màn Môn học ghi `4 môn`, `8 lớp`. Chưa xác định là lọc theo học kỳ có chủ đích hay lỗi.
2. **Thông báo rỗng của tìm lớp là `Chưa có lớp nào`**, không phải `Không tìm thấy lớp` như đoán từ code.
   Kỳ vọng đã sửa theo máy, không theo câu trả lời của agent.
3. **Remote Config lấy giá trị từ Console thật**: máy hiện `Loại tệp: docx, md, pdf`, khác thứ tự default
   trong code (`pdf, docx, md`).
4. **Đồng bộ FastAPI từng bị bỏ qua trên máy thật**: khi có Firebase, app ghi thẳng Firestore nên outbox
   SQLite không nhận gì (log server chỉ có `/sync/pull`). Đã nối: mỗi lượt ghi Firestore thành công thì ghi
   diff vào outbox → `/sync/push` (`firestore_academic_service.dart`, test `firestore_sync_outbox_test.dart`).
5. **ARTEMIS để task "mồ côi"**: dừng runner phía client không dừng task trên daemon; task cũ chạy tiếp
   25 phút và chặn hàng đợi. Phải gọi `POST /api/stop` cho từng session đang `running`.
6. `uiautomator dump` hỏng trong lúc ARTEMIS giữ UIAutomator2, nên chỉ hiệu chuẩn được khi không có task chạy.

## 06/11/2026 — Chuyển sang bộ flow (`--suite flows`), chưa chạy xong

10 flow bám Lab 2 F1/F2/F3 + backend (`e2e_test/flows.py`, mô tả ở `docs/test-plan.md` §3b). Lượt đầu bị dừng
theo yêu cầu khi FL01 đang chạy (task `aaadfd4e` đã gõ tên `E2E Flow 223322`); **chưa có kết quả flow nào**.
Model chuyển sang `gemini/gemini-3.6-flash` cho lượt sau (bản DeepSeek: `config/artemis.jsonc.deepseek-20261106`).

## Việc tiếp theo

- Chạy `--suite flows --runs 3` (ước tính 1,5–2,5 giờ với DeepSeek; Gemini nhanh hơn).
- Hiệu chuẩn màn đánh giá/phiên bản (FL04–FL07) bằng `uiautomator dump` khi không có task chạy.
- Phiên khám phá 15–30 phút ở profile `pro`.

## 06/11/2026 23:00 — Bộ flow, lượt 2–3 (dừng giữa chừng)

- Lượt 2 (realme, Gemini `gemini-3.6-flash`): FL01 task `4059892c` FAIL sau 2 bước — Gemini trả `503`
  rồi `LLM call timed out after 180 seconds`. Lỗi model, không phải app. Sau đó realme rớt USB.
  Đã quay về DeepSeek (bản Gemini lưu ở `config/artemis.jsonc.gemini-20261106`).
- Lượt 3 (Xiaomi `49BEF6B6TCRSJNQW`, DeepSeek, APK build lại 23:05 có endpoint sync + vá outbox):
  FL01 task `aba6d266` hết 900 s sau 55 bước. **App bị ANR thật** trên Xiaomi:
  `ANR in com.example.srs_review_ai_mobile … Reason: Input dispatching timed out (Application does not
  have a focused window)` lúc 23:13:42 và 23:23:11 (`adb logcat`). Bản debug ~200 MB (JIT) — cần thử lại
  với `--profile`/`--release` trước khi kết luận là lỗi app.
- Lỗi runner: hết giờ phía client không dừng task trên daemon → `aba6d266` vẫn chạy và runner force-stop
  app giữa chừng. Đã sửa: `run_suite.py` gọi `stop_running()` khi `client.run` ném lỗi.

## 07/11/2026 00:40 — Bộ flow, lượt 4: FL02–FL08 × 1 trên Xiaomi (DeepSeek)

| Flow | Kết quả | Giây | Trace | Ghi chú |
|---|---|---|---|---|
| FL01 | FAIL | 900 | `aba6d266` | lượt 3: app ANR, hết giờ |
| FL02 | FAIL | 181 | `25ec65bd` | chặn lưu đúng (14→14) nhưng **không hiện lỗi** (`error_text: ""`) |
| FL03 | PASS | 303 | `c5aa2716` | |
| FL04 | FAIL | 213 | `727ec969` | luồng đúng (điểm 78, chờ 6→5); app ghi `Đã phê duyệt` (kỳ vọng viết sai `Đã duyệt`); **0 `POST /review` trong log FastAPI** |
| FL05 | PASS | 868 | `eda88b49` | |
| FL06 | FAIL | 1200 | — | hết giờ, runner đã dừng task (bản sửa hoạt động) |
| FL07 | FAIL | 900 | — | hết giờ, không có báo cáo |
| FL08 | PASS | 293 | `1b0ec1fe` | Back hệ thống giữ bộ lọc `Hạn nộp`, app không thoát |

Tỉ lệ: 3/8 PASS. Trong 5 FAIL: 3 lượt hết giờ (FL01, FL06, FL07) chưa cho biết app đúng hay sai;
FL04 có 1 kỳ vọng sai chữ cần sửa trong `flows.py`; còn lại 2 điểm cần quyết: app không gọi FastAPI `/review`
khi AI review (điểm lấy từ đâu?) và form tạo dự án không báo lỗi khi trống tên.
