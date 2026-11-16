# Kế hoạch kiểm thử E2E bằng ARTEMIS — Lab 3 §7

App: `com.example.srs_review_ai_mobile` (Flutter, nhánh `feat/docker-setup`), vai Giảng viên.
Máy: realme RMX3686, Android 14, serial `UGKFPBYDTGE67HGY`, cắm USB. Không dùng máy ảo.
Công cụ: ARTEMIS (`/Volumes/SSD/AppData/artemis`, commit `351ca84`) gọi qua `ArtemisClient`;
model `gemini/gemini-3.6-flash` (fallback `gemini-3.5-flash-lite`; bản DeepSeek cũ ở `config/artemis.jsonc.deepseek-20261106`), profile `flash` (phiên khám phá dùng `pro`).

Mã nguồn bộ test: [e2e_test/cases.py](../e2e_test/cases.py) (12 ca theo chức năng), [e2e_test/flows.py](../e2e_test/flows.py) (10 flow Lab 2, §3b),
[e2e_test/run_suite.py](../e2e_test/run_suite.py) (runner). Nhật ký: [docs/evidence/artemis-run-log.md](evidence/artemis-run-log.md)
và `e2e_test/results/<ngày>.jsonl` (mỗi lượt một dòng: trace ID, thời gian, JSON quan sát, từng kiểm tra).

## 1. Nguyên tắc chấm

1. **SUCCESS của ARTEMIS không phải PASS.** Một lượt chỉ PASS khi cả ba điều kiện đúng: agent báo
   `succeeded`, báo cáo cuối là JSON đúng schema, và **mọi giá trị trong JSON khớp kỳ vọng**.
   Đã đo được lý do: hai lượt đầu tiên (06/11) `succeeded=True` nhưng `result.output = null`.
2. **Kỳ vọng không lấy từ lời agent.** Nguồn kỳ vọng: fixture `mobile/assets/fixtures/academic.json`,
   số đo trên máy bằng `adb shell uiautomator dump` ở lượt hiệu chuẩn, và với ca đồng bộ thì đọc
   DB server (`server/.cache/sync.sqlite3`, mở chỉ đọc).
3. **Điều kiện đầu được dựng lại mỗi lượt:** `am force-stop` + mở app, `adb reverse tcp:8010` (có mạng
   tới server sync). Ca TC12 tự cắt mạng trước và nối lại sau.
4. **Mỗi ca chạy 3 lần.** Báo cáo theo ca: số lượt, số đạt, tỉ lệ, thời gian trung bình, trace ID.
   Ca có 1–2/3 đạt gọi là *flaky* và phải có giải thích từ trace (bước nào sai, vì sao).

## 2. Điều kiện chung

| # | Điều kiện | Cách kiểm |
|---|---|---|
| P1 | Máy cắm USB, đã bật gỡ lỗi USB, màn hình không khoá | `adb devices` thấy serial |
| P2 | APK debug bản mới nhất đã cài, build với `--dart-define=SYNC_BASE_URL=http://127.0.0.1:8010` | `adb shell dumpsys package <app> \| grep lastUpdateTime` |
| P3 | Đã đăng nhập bằng tài khoản Google **test**, vai Giảng viên | Tab Tổng quan hiện `Xin chào, Le Huy Tuong` |
| P4 | Server FastAPI chạy ở `127.0.0.1:8010`, `adb reverse tcp:8010 tcp:8010` | `curl -s 127.0.0.1:8010/health` |
| P5 | ARTEMIS daemon + Web UI ở `:8020`, config model DeepSeek | mở http://localhost:8020 |
| P6 | Remote Config trên Firebase Console: `max_upload_file_size_mb`, `allowed_srs_file_types` đã publish | ảnh chụp Console |

## 3. Ca kiểm thử

Cột **Kiểm** liệt kê các giá trị runner assert (ngoài `succeeded` và "báo cáo là JSON").

| ID | Luồng | Điều kiện đầu | Bước (goal giao cho ARTEMIS) | Kết quả mong đợi | Kiểm |
|---|---|---|---|---|---|
| TC01 | Lab 2 · Tổng quan | P1–P5 | Mở tab Tổng quan, đọc lời chào và 6 thẻ thống kê | `Xin chào, Le Huy Tuong`; thẻ = 3 môn / 7 lớp / 6 chờ đánh giá / 5 đang đánh giá / 0 đăng ký chờ / 10 dự án cần xử lý | tên + 6 số chính xác |
| TC02 | Lab 2 · Môn học | P1–P5 | Từ Tổng quan bấm thẻ Môn học, đọc mã mọi môn (cuộn hết) | Danh sách 4 môn (thẻ TC01 ghi 3 — xem phát hiện 1 trong nhật ký) | số môn = 4, mã ⊆ dữ liệu đo trên máy |
| TC03 | Lab 2 · Tìm kiếm | P1–P5 | Mở danh sách lớp, gõ `SE17` vào ô "Tìm lớp..." | Chỉ còn các lớp có `SE17` trong tên (SE1701/02/03) | mọi kết quả chứa `SE17` và có trong fixture |
| TC04 | **Nhánh rỗng/lỗi** · Tìm kiếm | P1–P5 | Như TC03 nhưng gõ `ZZZ999` | 0 lớp; hiện trạng thái rỗng `Chưa có lớp nào` | `result_count = 0`, thông báo chứa "Chưa có lớp nào" |
| TC05 | Lab 2 · Dự án → chi tiết | P1–P5 | Tab Dự án → bấm `Smart Campus Management`, đọc tên/lớp/trạng thái | Màn chi tiết đúng dự án, có lớp và trạng thái | tên đúng, lớp ∈ fixture, trạng thái không rỗng |
| TC06 | **Tương tác Android gốc** · Back | P1–P5 | Vào chi tiết `Smart Campus Management` rồi nhấn **nút Back hệ thống** (không phải mũi tên trong app) | Quay về danh sách dự án, app không thoát | `detail_title` đúng, `after_back_screen = list`, `app_still_open = true` |
| TC07 | Lab 2 · Đánh giá | P1–P5 | Tab Đánh giá → đọc số chờ đánh giá → mở tài liệu đầu tiên | 8 tài liệu chờ (khớp thẻ TC01); mở được tài liệu, dự án của nó có thật | `waiting = 8`, tài liệu không rỗng, dự án ∈ fixture |
| TC08 | Lab 2 · Thông báo | P1–P5 | Tab Thông báo → đếm, chép ≤3 tiêu đề | Đếm được; nếu 0 thì hiện trạng thái rỗng | `count` là số ≥ 0 và nhất quán với danh sách tiêu đề |
| TC09 | Lab 2 · Tài khoản | P1–P5 | Tab Tài khoản → đọc họ tên, email, vai trò | `Le Huy Tuong`, `lehuytuong2005@gmail.com`, `Giảng viên` | 3 giá trị chính xác |
| TC10 | **Lab 3 · Remote Config** | P1–P6 | Tab Tài khoản → khu "KHU VỰC DEMO LAB 3" → dòng Remote Config | `Giới hạn tải lên: 30 MB · Loại tệp: docx, md, pdf` đúng với giá trị đang publish trên Console | N và danh sách loại tệp khớp Console (hằng số `RC_*` trong `cases.py`) |
| TC11 | **Nhánh lỗi** · Form validate | P1–P5 | Bấm "Tạo học kỳ", để trống mọi ô, bấm lưu, chép lỗi, bấm Hủy | Form báo lỗi, KHÔNG tạo học kỳ | `saved = false`, có `error_text` |
| TC12 | **Offline sync** (SQLite outbox → `/sync/push`) | P1–P5; runner cắt `adb reverse` trước khi giao việc | Tạo học kỳ tên `E2E <giờ>` khi mất mạng; runner nối mạng lại | Học kỳ hiện ngay trên máy (lưu SQLite); server **chưa** có khi offline; trong ≤ 90 s sau khi có mạng, server có **đúng 1** bản ghi | agent thấy tên vừa tạo; DB server: 0 bản ghi lúc offline, 1 bản ghi sau khi online |

## 3b. Bộ flow Lab 2 (mặc định của runner, `--suite flows`)

Mỗi flow là một hành trình nhiều màn, kiểm cả UI lẫn backend (DB sync `server/.cache/sync.sqlite3`,
log `/tmp/srs-sync-server.log`). Kỳ vọng so **trước/sau** trong cùng lượt, không dùng số cứng.
**Trạng thái: đã viết, chưa chạy xong lượt nào trên máy** (lượt đầu dừng giữa FL01 theo yêu cầu).

| ID | Lab 2 | Hành trình | Kiểm |
|---|---|---|---|
| FL01 | F1 | Tạo dự án mới → thấy trong danh sách | tên hiện trên máy; `/sync` có bản ghi projects mới |
| FL02 | F1 · lỗi | Tạo dự án để trống tên → lưu → Hủy | có lỗi validate, không tạo bản ghi |
| FL03 | F1 | Tìm lớp không có → xoá tìm (về 7 lớp) → mở SE1701 | rỗng → đủ lớp → chi tiết đúng lớp |
| FL04 | F2 | Mở tài liệu chờ → AI review → Duyệt | số chờ −1; log server có `POST /review` 200 |
| FL05 | F2 · lỗi | "Yêu cầu sửa" với ghi chú trống | form chặn, trạng thái không đổi |
| FL06 | F2 · backend sập | Cắt `adb reverse` → review lỗi → 120 s sau nối lại → thử lại | thấy lỗi, rồi thành công |
| FL07 | F3 | Xem phiên bản và lịch sử tài liệu | có ≥1 phiên bản, lịch sử không rỗng |
| FL08 | F3 · Android | Thông báo "Hạn nộp" → chi tiết → **Back hệ thống** | quay về danh sách, app không thoát |
| FL09 | Offline | Tạo học kỳ khi mất mạng → nối mạng | server có **đúng 1** bản ghi |
| FL10 | Account | Hồ sơ + Remote Config 30 MB → đăng xuất → Back → account picker → đăng nhập lại | thông tin đúng; về lại Tổng quan |

Chạy (bật OBS collection **ARTEMIS E2E** → Start Recording trước):

```sh
cd /Volumes/SSD/AppData/artemis
ARTEMIS_BASE_URL=http://127.0.0.1:8020 .venv/bin/python \
  /Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/e2e_test/run_suite.py --suite flows --runs 3
# một flow: ... --suite flows --runs 1 --only FL01
```

Ước tính: 2–6 phút/flow/lượt → 3×10 lượt mất 1–2,5 giờ. Muốn ngắn: `--runs 1` (~20–40 phút).
FL04–FL07 chưa hiệu chuẩn bằng `uiautomator dump`; nên chạy `--runs 1` trước rồi sửa nhãn.

Độ phủ theo yêu cầu đề:

- Luồng Lab 2: TC01, TC02, TC03, TC05, TC07, TC08, TC09.
- Nhánh lỗi/thay thế: TC04 (tìm không thấy), TC11 (validate form).
- Tương tác Android gốc: TC06 (nút Back hệ thống). Ngoài ra luồng đăng nhập Google mở **account
  picker native** — xem §5, chạy tay vì cần tài khoản test và không lặp tự động được an toàn.
- Lab 3: TC10 (Remote Config hiện trên màn hình), TC12 (SQLite + đồng bộ server).

## 4. Cách chạy

```sh
cd /Volumes/SSD/AppData/artemis
ARTEMIS_BASE_URL=http://127.0.0.1:8020 .venv/bin/python \
  /Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/e2e_test/run_suite.py --suite functions --runs 3
# chỉ vài ca:  ... run_suite.py --runs 3 --only TC10,TC12
```

Runner in mỗi lượt một dòng `TC.. #n <giây> <trace_id> PASS|FAIL <kiểm tra hỏng>` và cuối cùng là
bảng tổng hợp. Xem lại từng bước: Web UI http://localhost:8020 → Replay theo trace ID, hoặc
`sqlite3 traces/data_engine.db "select step_number, action_taken from steps where session_id='<id>'"`.

### Hiệu chuẩn trước lượt chính

Trước khi chạy 3×12, mở từng màn bằng tay và chụp cây UI:

```sh
adb -s UGKFPBYDTGE67HGY shell uiautomator dump /sdcard/ui.xml
adb -s UGKFPBYDTGE67HGY pull /sdcard/ui.xml /tmp/ui.xml
```

Đối chiếu với kỳ vọng ở §3. Sửa hằng số đánh dấu `# CALIBRATE` trong `cases.py` khi số đo trên máy
khác fixture, và ghi lý do vào nhật ký. Không sửa kỳ vọng theo câu trả lời của agent.

## 5. Ca chạy tay (ghi kèm, không tính vào 12 ca tự động)

| ID | Luồng | Bước | Kỳ vọng | Bằng chứng |
|---|---|---|---|---|
| M1 | Đăng nhập Google (account picker native) | Đăng xuất → "Đăng nhập với Google" → chọn tài khoản test trong hộp thoại hệ thống | Về tab Tổng quan với lời chào đúng người | ảnh màn hình + Firebase Console › Authentication |
| M2 | Analytics | Đăng nhập, mở một tài liệu SRS; trên Console bật DebugView (`adb shell setprop debug.firebase.analytics.app <app>`) | Thấy `login`, `view_srs_detail` trong DebugView | ảnh DebugView |
| M3 | Remote Config real-time | Đổi `max_upload_file_size_mb` trên Console rồi publish, app đang mở ở tab Tài khoản | Dòng Remote Config đổi số mà không cần mở lại app | 2 ảnh trước/sau + ảnh Console |

## 6. Phiên khám phá (15–30 phút)

- Profile `pro`, một goal mở: *"Khám phá app như giảng viên mới dùng lần đầu trong 20 phút: thử mọi tab,
  tìm kiếm, mở chi tiết, tạo rồi huỷ form, xoay màn hình, Back hệ thống. Ghi lại mọi chỗ crash,
  treo, chữ bị cắt, nút không phản hồi, số liệu mâu thuẫn giữa các màn."*
- Kết quả ghi vào nhật ký: thời lượng thật (từ `sessions.start_time/end_time`), số bước, danh sách
  lỗi (mỗi lỗi: màn, bước tái hiện, ảnh bước trong trace, mức độ), và lỗi nào đã tái hiện lại bằng tay.

## 7. Rủi ro đã biết

- **DeepSeek có thật sự nhìn ảnh hay không: chưa kiểm chứng.** App Flutter đưa chữ ra cây UI, nên các
  ca trên đúng được kể cả khi model chỉ đọc chữ.
- **4 test widget/VM của dashboard đỏ ở upstream `cf7b2b5`** (tái hiện trên worktree sạch, không liên
  quan code sync). Không chặn E2E vì màn Tổng quan trên máy vẫn hiện đúng số.
- TC12 phụ thuộc backoff đồng bộ (2 s → 60 s); runner chờ tối đa 90 s.
- Ca có thao tác ghi (TC11 huỷ, TC12 tạo học kỳ) để lại dữ liệu `E2E hhmmss` trên máy và server — đây
  là dữ liệu demo, không phải dữ liệu thật.
