# WP0 — Khóa baseline và kiểm kê đầu vào

Ngày: 05/11/2026, Asia/Saigon. HEAD khi chạy: `473bf720d90a43498229901611e70042062324a8`,
nhánh `feat/firebase-setup`. Baseline khảo sát lịch sử của plan là `f3de9fe`;
WP0 đo lại trên mốc hiện tại, không chép kết quả cũ.

Trạng thái WP0: **LOCAL_PASS** cho phần đo được trong máy này; phần Firestore và
nguồn dữ liệu thật đang **WAITING_USER** (mục 8). Không WP nào VERIFIED, không
đụng cloud/device, không chạy app test và không gọi LLM trong lượt này.

## 1. Phạm vi và việc đã làm

- Đọc lại AGENTS/README/project-status/Plan 13/progress/handoff; chạy
  `python tools/project_context.py` → exit 0.
- Ghi inventory working tree **trước khi sửa**: 5 file docs đã sửa, 0 file
  untracked. Không reset/clean/stash, không đụng `promt.txt` hay `.env`.
- Thêm `tools/wp0_baseline.py` (inventory / backup / verify) và 16 test mới ở
  `tools/tests/test_wp0_baseline.py`.
- Sinh manifest kiểm kê, backup công việc có sẵn ra **ngoài repo**, verify hash.
- Không đọc credential, không mở socket, không deploy Rules, không ghi cloud.

## 2. Công cụ và hợp đồng

`tools/wp0_baseline.py` có ba lệnh:

| Lệnh | Việc | Exit 1 khi |
|---|---|---|
| `inventory` | đo từng nguồn, ghi JSON manifest, in bảng | nguồn `required` vắng mặt, hoặc bất kỳ nguồn `unreadable` |
| `backup` | copy phần chưa commit + diff ra ngoài repo | git lỗi hoặc không copy được |
| `verify` | đọc lại backup, băm lại từng bản copy | thiếu bản copy, hash lệch, thiếu diff |

Các quyết định phải giữ khi sửa công cụ:

- `absent` (đã đo, không tồn tại) khác `unreadable` (có nhưng không đọc được).
  Gộp hai thứ này là cách một inventory rỗng giả làm bằng chứng "0 bản ghi".
- `--require KEY` nâng một nguồn thành bắt buộc; test khẳng định thiếu nguồn bắt
  buộc thì exit 1 chứ không in bảng xanh.
- SQLite mở `mode=ro` + `PRAGMA query_only`, chỉ đếm dòng theo bảng; test so
  hash trước/sau để chứng minh không ghi vào cache đã trả tiền.
- Đường dẫn tuyệt đối bị thay bằng `<repo>`, `<APPDATA>`, `<LOCALAPPDATA>`,
  `<TEMP>` để manifest commit được mà không lộ tên người dùng.
- `git status -z` để tên file tiếng Việt không bị Git quote thành chuỗi escape.

## 3. Kết quả kiểm kê

Manifest: [wp0-inventory-2026-11-05.json](wp0-inventory-2026-11-05.json)
(14.304 B, sha256 `2424aa7836cec864b5e82e8dc56962725f8d5407d787ff0ebc3ef40360a90d88`).

| Nguồn | Trạng thái | File | Bytes | Ghi nhận |
|---|---|---:|---:|---|
| `server/.uploads` | present | 6 | 4.629.878 | 2 upload key + `.docmap.json` + `.meta.json` |
| `server/.cache` | present | 3 | 1.021.576 | `cache.sqlite3` 4.096 B + WAL 984.712 B + shm 32.768 B |
| `server/.shares` | present | 31 | 991 | HTML chia sẻ |
| `server/.classes` | absent | 0 | 0 | chưa từng ghi lớp trên máy này |
| `server/.submissions` | absent | 0 | 0 | chưa từng ghi bài nộp |
| `desktop` Sembast | absent | 0 | 0 | `<APPDATA>\co.resonancetech\srs_review_ai\srs_review_ai.db` |
| Chrome profile cố định | absent | 0 | 0 | `<LOCALAPPDATA>\srs-review-ai\chrome-profile` |
| Profile tạm `flutter_tools` | present | 11 | 5.447 | origin `http://localhost:56119` |
| Firestore | not_measured | — | — | cần credential (mục 8) |

Đếm dòng SQLite: `cache_entries = 63`, `cache_meta = 1`. Đây là kết quả chấm
đã trả tiền từ các lượt chạy trước; manifest chỉ giữ hash, không giữ payload.

## 4. Đọc kết quả: dữ liệu thật hay fixture?

- `.uploads`: hai upload key cùng một PDF `Chương 1 - Tổng quan về nghiên cứu
  khoa học.pdf`, **cùng sha256** `2548d964950a99f28fabd0fe99c9a7c211fa72dab82ddf8264c2e5593ed23051`,
  2.291.188 B mỗi bản. Đây là lần thử upload ngày 26/09, không phải SRS của lớp.
- `.shares`: 5 × `<html/>` (7 B), 25 × `<html><body>báo cáo</body></html>` (35 B),
  1 × tiêu đề "Báo cáo OTES — verdict 7/10" (81 B). Toàn bộ là placeholder test,
  không phải report thật.
- `.classes`/`.submissions` không tồn tại; đã tìm `srs_review_ai.db` trong
  `%LOCALAPPDATA%`, `%APPDATA%`, `F:\study\PRM` và `Documents` — không thấy.
  Đây là phép đo trên máy này, **không** phải kết luận hệ thống không có dữ liệu.
- Profile Chrome cố định của `desktop/tool/dev_web.ps1` không tồn tại. Profile
  tạm `flutter_tools.3427e008` có 11 file / 5.447 B; quét bytes thấy không có
  chuỗi `srs`/`session`/`project`/`otes` nào. Nhiều khả năng là một lần chạy
  rỗng, nhưng **chưa mở app để xác nhận** — không ghi thành "không có lịch sử".

## 5. Backup công việc có sẵn

| Mục | Giá trị |
|---|---|
| Đích | `%USERPROFILE%\srs-review-ai-backups\wp0-backup-20261105T161321Z` (ngoài repo) |
| Nội dung | 5 docs đã sửa + `tools/wp0_baseline.py` + test + manifest kiểm kê = 8 file |
| Diff working tree | `working-tree.diff`, 8.185 B |
| Verify | exit 0 — "checked 8 file(s)", drift 0, "all hashes match" |
| Manifest backup | [wp0-backup-manifest-2026-11-05.json](wp0-backup-manifest-2026-11-05.json), 3.124 B, sha256 `588b63270b9892c47f7619f74332190888e788a974e7693212bb7f76c82a61ab` |

Backup không chứa `.env`, payload upload hay credential; bản sao manifest trong
repo chỉ có đường dẫn tương đối và hash.

Verify chạy ngay sau backup (drift 0). Ba file nằm trong backup được sửa tiếp
**sau** mốc đó (progress, project-status, test), nên chạy lại `verify` cuối lượt
báo `worktree drift since backup: 3` và vẫn `all hashes match`, exit 0 — drift
là thay đổi có chủ đích của lượt, không phải backup hỏng. Tính toàn vẹn của bản
copy luôn được kiểm bằng hash từng file, độc lập với drift.

## 6. Lệnh đã chạy và exit code (đo tại lượt này)

| Lệnh | Exit | Kết quả |
|---|---:|---|
| `python tools/project_context.py` | 0 | HEAD `473bf72`, 12/12 start file đọc được |
| `python -m py_compile tools/wp0_baseline.py` | 0 | |
| `python tools/wp0_baseline.py inventory` | 0 | 4 present, 4 absent, 1 not_measured, 0 unreadable |
| `python tools/wp0_baseline.py inventory --out docs/evidence/wp0-inventory-2026-11-05.json` | 0 | manifest 14.304 B |
| `python tools/wp0_baseline.py backup --dest %USERPROFILE%\srs-review-ai-backups` | 0 | 8 file |
| `python tools/wp0_baseline.py verify <backup>` | 0 | hash khớp, drift 0 |
| `python -m unittest discover -s tools/tests -v` | 0 | 27 test OK (16 mới + 11 cũ) |
| `server/.venv/Scripts/ruff.exe check server` | 0 | All checks passed |
| `server/.venv/Scripts/ruff.exe format --check server` | 0 | 84 files already formatted |
| `python tools/check_guardrails.py` | 1 | 61 vi phạm có sẵn (layering 9, tokens 50, full-screen 2); luật line endings OK |
| `git diff --check` | 0 | đạt (đã bỏ blank line cuối `13-progress.md`) |
| Kiểm UTF-8/CR/link nội bộ 7 file mới+sửa | 0 | 0 lỗi, 0 CR, 0 link hỏng |
| `python tools/wp0_baseline.py verify <backup>` (chạy lại cuối lượt) | 0 | 8 bản copy khớp hash, drift 3 |

## 7. Chưa kiểm và điểm chặn

1. **Firestore** (grants, `users/{uid}/projects`, reports, mirror crash): chưa
   đo. Máy này không có Application Default Credentials
   (`%APPDATA%\gcloud\application_default_credentials.json` không tồn tại), không
   có `GOOGLE_APPLICATION_CREDENTIALS`, không có service-account JSON trong repo.
2. **Nguồn dữ liệu thật**: máy này chỉ có fixture/test; chưa biết lớp/bài
   nộp/báo cáo thật nằm ở đâu (máy khác, backup, hay Firestore).
3. **Lịch sử web/desktop cũ**: profile Chrome cố định và DB Sembast không tồn tại
   trên máy này; nếu người dùng từng chạy ở nơi khác thì cần đường dẫn cụ thể.
4. Không chạy: Flutter/Flutter tests, pytest server, Rules emulator, device,
   Cloudinary, FCM/RC/Analytics/Crashlytics, migration (thuộc WP1+).

## 8. Yêu cầu người dùng (mẫu Plan 13 §5.2)

```text
Đang ở WP: WP0 — phần local đạt (LOCAL_PASS), đang chờ đầu vào ngoài repo.

Đã hoàn tất và kiểm thử:
- tools/wp0_baseline.py (inventory/backup/verify) + 16 test; toàn bộ 27 test tools pass.
- Inventory 9 nguồn có hash; manifest và backup manifest đã lưu trong docs/evidence.
- Backup 8 file ra ngoài repo, verify hash exit 0, drift 0.

Điểm đang chặn:
1. Firestore chưa đo được: thiếu credential Admin.
2. Chưa xác định dữ liệu học vụ thật nằm ở đâu; máy này chỉ có fixture 26/09.
3. Không có profile Chrome cố định / Sembast trên máy này.

Bạn cần làm (chọn mục nào bạn muốn mở khoá trước):
1. Dữ liệu thật: cho biết lớp/bài nộp/báo cáo thật đang ở máy nào, thư mục nào
   (ví dụ ổ ngoài, bản backup, hay chỉ có trên Firestore).
2. Firestore (khi muốn đo): trên máy này chạy
   gcloud auth application-default login
   bằng tài khoản có quyền đọc project srs-ai-prm, hoặc đặt service-account JSON
   ở một đường dẫn ngoài repo và đặt biến môi trường GOOGLE_APPLICATION_CREDENTIALS.
   Không gửi key/JSON qua chat.
3. Web cũ: nếu từng có lịch sử trên bản web, cho biết profile Chrome cũ nằm ở đâu
   (đường dẫn thư mục), hoặc xác nhận chưa từng có để bỏ qua nguồn này.

Cần bạn trả lại:
- Đường dẫn local hoặc mô tả vị trí dữ liệu (không kèm nội dung file).
- Xác nhận đã đăng nhập ADC xong (không cần dán token).

Sau đó agent kiểm bằng:
- python tools/wp0_baseline.py inventory --require <nguồn> và so hash manifest.
- Với Firestore: probe google.auth.default() rồi liệt kê collection và đếm bản ghi,
  chỉ in số lượng/không in PII.
```

## 9. Bước tiếp theo

WP0 đạt điều kiện qua chặng ở phần local: có baseline, manifest đủ, và biết rõ
nguồn chưa truy cập được. Việc đo Firestore/nguồn thật ở lại WAITING_USER và
không chặn **WP1** (guardrails/toolchain), vốn chỉ dùng repo local.

WP1 sẽ bắt đầu bằng việc đo lại 61 vi phạm guardrails (layering 9, design tokens
50, full-screen 2) và pin Flutter/Dart theo plan — chưa làm trong lượt này.
