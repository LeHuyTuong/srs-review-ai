# Plan 12 — Chạy hết phần còn lại (bản giao việc cho một model khác, 2026-09-27)

> **Cách dùng file này.** Bạn là model được giao toàn bộ repo + file này, không có
> lại hội thoại cũ. Đọc **§0 trước khi làm bất cứ việc gì**, rồi §1 (bẫy), rồi làm
> tuần tự **WP0→WP8**. Mọi con số trong plan này **đã đo ngày 2026-09-27**; repo có thể
> đã đổi — **đo lại rồi hãy trích dẫn**, đừng copy số vào báo cáo.
>
> Plan này **không thay thế** `AGENTS.md`. `AGENTS.md` là luật, vẫn đúng, và bạn
> **phải đọc hết**. Plan này là thứ tự việc + điều kiện dừng.

---

## 0. Boot sequence (30 phút, bắt buộc)

Đọc theo đúng thứ tự này. Lý do ghi kèm để bạn biết lúc nào được phép bỏ qua.

| # | File | Vì sao phải đọc trước |
|---|---|---|
| 1 | `AGENTS.md` (gốc repo) | Luật + **mọi bẫy đã trả giá**. Bỏ qua là tái tạo bug cũ. |
| 2 | `docs/plans/7-review-engine-v2-2026-09-15.md` | Kết luận từ 4 lượt chạy thật: đơn vị output của app, 8 check giá trị nhất, workflow hai pass. |
| 3 | `docs/adr/README.md` → lần lượt `0010`, `0011`, `0014`, `0015` | Pacing/batch, persistence, modal toàn màn hình (không bottom sheet), role ≠ form factor. Bốn ADR này chặn nhiều quyết định nhất. |
| 4 | `docs/plans/10-closing-the-open-gates-2026-09-26.md` §0, §2, §3 | Ba gate còn mở và **vì sao** chain 2/3 chưa được cộng vào thang điểm. |
| 5 | `docs/plans/11-teacher-app-2026-09-27.md` (cả file) | App giáo viên: thiết kế identity, ba tầng server, tầng app, và **kết quả Tầng 1 đã làm xong**. |
| 6 | `review-rules/README.md` + `review-rules/adapters/app-port-map.md` | Luật chấm sống ở đây, không trong code/prompt. |

```sh
# Chạy được ngay (Windows; macOS/Linux dùng .venv/bin/python)
cd server && .venv\Scripts\python.exe -m pytest tests -q      # 238 test, 1 skip
cd app    && flutter test                                     # 946 test
python tools\check_guardrails.py                              # 8 nhóm luật, quét mọi file
```

**Trạng thái ngày 2026-09-27, sau WP2 (mốc so sánh của plan này):** app **946/946**,
server **262 passed + 1 skipped** (trước WP2: 238), guardrails **8/8**. Ruff trong venv
khớp pin của CI, và `ruff check` + `ruff format --check` đều sạch.
`docs/roadmap.md` ghi một con số cũ hơn — **đừng sửa code để khớp với số trong docs**.


## 1. Chín cái bẫy sẽ ăn thời gian của bạn (tất cả đều đã ăn của ai đó)

1. **Mọi file `.py` trong `server/` là CRLF.** Một lệnh replace nhiều dòng, hoặc
   editor yêu cầu match chính xác cả block, sẽ **fail im lặng** hoặc chèn LF vào
   giữa file CRLF → `ruff format --check` của CI đỏ. Cách an toàn: write một script
   Python nhỏ đọc `newline=""`, chuẩn hoá `\r\n`→`\n`, replace, rồi viết lại đúng
   kiểu cũ. **Luôn đọc lại file sau khi vá để xác nhận.**
2. **`pytest` không có trên PATH.** `python3 -m pytest` luôn ra
   `No module named pytest`. Chỉ `.venv` (Python 3.11) mới có. Kết luận "test hỏng"
   sau khi gọi `pytest` trần là chẩn đoán sai.
3. **Chạy đúng hai lệnh của CI trước khi báo xong: `server\.venv\Scripts\ruff.exe
   check server` và `format --check server`.** Ruff **có** trong venv (0.14.14, khớp pin
   `ruff~=0.14.0`) dù không có trên PATH. Bỏ qua bước này thì CI đỏ mà bạn không biết —
   nó đã xảy ra: hai file test mang nợ format từ lúc viết, chỉ lộ ra khi người sau chạy
   đúng lệnh CI.
4. **`flutter test` phải chạy sau `dart format`.** CI chạy
   `dart format --output=none --set-exit-if-changed .` và
   `flutter analyze --fatal-infos --fatal-warnings`. Code đúng nhưng chưa format = đỏ.
5. **`pdfx` là plugin native pdfium — chết trong mọi test runner trên host**, với hai
   thông điệp đánh lạc hướng (`Binding has not yet been initialized`, rồi
   `PlatformException(channel-error)`). Đã có `PdfSupportProbe` + fake
   (`_FakePageRenderer`) — **dùng cái có sẵn**, đừng bắt pdfx tự phán trong test.
6. **Đo lỗi overflow: `tester.takeException()` chỉ trả MỘT lỗi.** Phải bơm hết hàng
   đợi: `while ((e = tester.takeException()) != null)`. Và **`Expanded` bị bóp cạn
   không ném exception nào** — với app điện thoại phải **đo width**
   (`tester.getSize(...).width`), không đếm exception.
7. **`flutter run -d chrome` tạo Chrome profile mới + port mới mỗi lần** ⇒ IndexedDB
   gốc khác ⇒ Lịch sử "trông như mất". Dùng `app/tool/dev_web.ps1` (port + profile
   cố định).
8. **`ref.read(provider)` trong view-model phải nằm trong `try`.** Một provider tiện
   ích đọc lúc import (kéo theo `sharedPreferencesProvider` chưa override) làm nổ
   cả test không liên quan. Harness test override provider mới về `null` mặc định.
9. **File mới import plugin native phải được đăng ký trong `NATIVE_PLUGIN_RULES`** ở
   `tools/check_guardrails.py` **kèm seam** script kiểm lại được. **Đừng thêm ngoại lệ.**

Một giới hạn về phía bạn, không phải lỗi của repo: **model không đọc được ảnh trong
phiên harness**. Mọi phát biểu về quan hệ/bội số trong sơ đồ UML là **chưa kiểm
chứng** — chỉ annotation và text trích ra mới dùng được làm bằng chứng.

---

## 2. Work packages

Thứ tự là **phụ thuộc**, không phải thứ tự thú vị. Cột "Cần gì" là điều kiện tiên quyết;
WP nào thiếu điều kiện thì **dừng**, đừng làm vội rồi phải làm lại.

| WP | Việc | Cần gì | Rủi ro |
|---|---|---|---|
| WP0 | Dọn cây làm việc + commit theo lớp | — | thấp |
| WP1 | ADR 0016 (roster + quyết định giáo viên) | WP0 | thấp |
| WP2 | Server: lớp (roster) | WP1 | trung bình |
| WP3 | Server: quyết định của giáo viên | WP2 | thấp |
| WP4 | Server: activity + watermark | WP2, WP3 | thấp |
| WP5 | App: 3 màn hình giáo viên | WP2–WP4 | **cao** |
| WP6 | Đo chain 1 trên OTES thật (đóng AC4) | server tự host | trung bình |
| WP7 | Bộ dụng cụ gold set (**không tự tạo gold**) | WP6 | thấp / chặn người |
| WP8 | Ba gate M5 | khóa API thật + người duyệt chi phí | **cao** |

### WP0 — Dọn cây làm việc và commit theo lớp (30–45 phút)

**Vì sao làm trước tiên.** Cây làm việc hiện có khoảng 20 file sửa và 20 file mới
**chưa commit** (kể cả `server/app/infrastructure/submissions.py`, `docs/plans/9,10,11`,
`app/lib/core/role/`). Một lần `git checkout .` hoặc một lần rebase đúp là mất cả
phiên trước — còn hơn là mất sau khi đã làm thêm 3 WP.

1. `git status --short`, rồi chia thành **4 commit có nghĩa** (đừng commit 1 khối
   khổng lồ không đọc nổi):
   - **(a) app — chuỗi vision:** `lib/diagram_audit/services/vision_review_service.dart`,
     `lib/deterministic_checks/**`, `test/vision_chain_wiring_test.dart`,
     `test/cross_artifact_*.dart`, `test/contradiction_pass_vietnamese_test.dart`,
     `lib/features/workspace/view/workspace_modals.dart`, `lib/report_export/report_strings.dart`.
   - **(b) server — submissions:** `app/infrastructure/submissions.py`, `app/api/submissions.py`,
     `tests/test_submissions.py`, `tests/test_submission_time.py`, `app/api/deps.py`,
     `app/config/settings.py`, `app/main.py`.
   - **(c) docs:** `docs/plans/9,10,11,12*`, `docs/adr/0015*`, `docs/evidence/*2026-09-2*`.
   - **(d) app — role:** `lib/core/role/`, `test/app_role_test.dart`, `contracts/review.schema.json`.
2. **Rác cần xoá:** `game.html`, `tmp_ci_status.py`, `tmp_shots.py`, `tmp_screens/`,
   `.freebuff/`, `app/a1.out.txt`, `app/a2.out.txt`, `app/full.err.txt`.
3. **Phải hỏi người, không tự xoá:** một file `.mp4` lạ ở gốc repo (100 MB+,
   không thuộc dự án) và hai file `app/run.bat`, `server/run_server.bat`
   (tiện ích hay rác — quyết định của người).
4. `.gitignore` — thêm `docs/evidence/scripts/.vision-probe-cache.json` (cache sinh
   ra lúc chạy) và pattern cho file `.out.txt`. **Dùng pattern cụ thể, đừng dùng
   `*.txt` kiểu đại phà** — trong repo này `.md`/`.json` cũng quan trọng.
5. `docs/roadmap.md`: dòng "Test estate" đang ghi `841/841 · 161 pass` — đã cũ. Sửa
   bằng số **bạn vừa đo**, kèm ngày.

**AC:** `git status` sạch (không còn rác), 3 suite xanh **sau khi commit** (chứng
minh commit không bỏ sót file), roadmap có số đo kèm ngày.
**Dừng khi:** chưa hỏi được về `.mp4` thì commit các nhóm khác, để `.mp4` untracked
và **ghi rõ trong báo cáo** — đừng âm thầm xoá tài sản của người.

### WP1 — ADR 0016: lớp học dạng capability, và quyết định của giáo viên (60 phút)

**Phải trước WP2–WP5.** ADR 0015 ghi rõ nguyên tắc của repo: *ADR trước, UI sau*.

File mới: `docs/adr/0016-class-roster-and-teacher-decisions.md` + **một dòng trong
`docs/adr/README.md`** (index là bắt buộc, không phải tuỳ chọn).

ADR **phải trả lời tường minh** bốn câu, nếu không có câu trả lời thì ADR chưa xong:

1. **Identity:** lớp được định danh bằng `class_id` 128-bit (`secrets.token_urlsafe`),
   giáo viên giữ nó **như giữ link share**. Ghi thẳng hai hệ quả: ai cầm nó thì xem
   được cả lớp, và **không có cách thu hồi** nếu học viên đã thấy link — đòn phòng
   thủ duy nhất là mint lớp mới. Cấm dùng từ "bảo mật" cho cơ chế này.
2. **Từ vựng quyết định:** hôm nay `status` chỉ có `submitted|reviewed`. Giáo viên
   cần Duyệt / Yêu cầu sửa → chốt tập `status` mới, ai là người quyết định, thời điểm
   nào ghi. **Không thêm trạng thái nào không có nơi dùng trong UI** (xem WP5).
3. **Host:** roster và submission là **file trên đĩa** ⇒ chỉ đúng với self-host. Ghi
   rõ là điều kiện bắt buộc (app giáo viên không được trỏ bản Vercel, vì tmpfs mất
   sạch). Nếu đổi sang serverless thì phải chuyển sang DB **trước khi** coi là P4.
4. **"Đã đọc" là watermark phía app**, không phải bảng phía server. Nói rõ hệ quả:
   đánh dấu đã đọc trên máy này **không** sang máy khác. Chấp nhận có chủ đích, ghi
   thẳng thay vì dựng nửa vời.

**AC:** ADR tồn tại + có dòng index; tìm từ khoá `revocation` phải ra câu trả lời tường
minh; tìm `self-hosted` phải ra điều kiện host.
**Dừng khi:** câu nào ADR trả lời bằng "chưa biết" → biến câu đó thành câu hỏi cho
người dùng, **đừng tự đoán rồi viết vào ADR như đã chốt**.


### WP2 — Server: lớp học (roster) — **full CRUD** (3–4 giờ)

Lớp là tầng dữ liệu mà **không có nó thì "danh sách lớp" chỉ là một màn hình rỗng**.
Phạm vi này viết lại theo **ADR-0017** (quyết định: giáo viên tạo lớp ngay trong app,
CRUD đủ bốn động tác, mỗi động tác mang uỹ quyền riêng).

**File:** `server/app/infrastructure/classes.py` (mới), `server/app/api/classes.py`
(mới), `server/app/main.py` (khởi tạo store), `server/app/api/deps.py` (getter +
`__all__`), `server/app/config/settings.py` (thư mục lưu),
`server/app/infrastructure/submissions.py` (`assign_class` / `unassign_class`),
`server/app/api/submissions.py` (nhận `class_id`), test mới.

**Route:**

| Route | Uỹ quyền | Việc |
|---|---|---|
| `POST /classes` | app token | Tạo lớp → trả `class_id` **+ `write_key`** (chỉ trả đúng một lần) |
| `GET /classes/{class_id}` | **không** (id là credential) | Lớp + danh sách submission, **mới nhất trước** |
| `PATCH /classes/{class_id}` | `X-Class-Key` | Đổi tên. **Không** đổi `class_id` |
| `DELETE /classes/{class_id}` | `X-Class-Key` | Gỡ lớp; submission thành *chưa gán* |
| `POST /classes/{id}/submissions` | `X-Class-Key` | Gán một submission vào lớp |
| `DELETE /classes/{id}/submissions/{sid}` | `X-Class-Key` | Bỏ gán |
| `POST /submissions` *(mở rộng)* | app token | Nhận `class_id`; lớp không tồn tại → **422** nêu tên field |

**Cách làm (bám khuôn `SubmissionStore`, không phát minh):**
- `ClassStore`: mỗi lớp một file JSON, `_is_safe()` chặn path traversal, file hỏng thì
  bỏ qua chứ không làm sập store. **ID do server mint** (`token_urlsafe(16)`), không
  nhận id từ client.
- **Wire store** đúng đường cũ: module-level trong `main.py` → getter ở `deps.py` →
  **thêm tên vào `__all__` của `deps.py`** (thiếu dòng này thì route lỗi lúc chạy).
- **`write_key`**: sinh cùng lúc với `class_id`, chỉ trả về **một lần** ở response tạo;
  lưu `sha256(write_key)`; so bằng `secrets.compare_digest`. Lấy file store ra không
  có quyền ghi.

**Ba luật, cả ba là lỗi đã từng xảy ra ở chỗ khác:**
1. **Mọi phép ghi cần uỹ quyền riêng, không dùng app token cho lớp.** App token là
   *shared secret* — nếu `PATCH`/`DELETE` nhận nó thì **mọi bản app đang cài (kể cả
   bản của nhóm) đều xoá được lớp của giáo viên**. Đây là năng lực mới trao cho mọi
   bản cài hiện có, và nó sẽ đến mà không ai báo.
2. **`class_id` nằm trên submission, không có danh sách trong file lớp.** Hai nơi phải
   khớp nhau thì sẽ lệch, và không có gì chặn một submission nằm trong hai lớp.
3. **`DELETE` lớp không được xoá bài của nhóm.** Xoá lớp = clear `class_id` ở các
   submission (chúng vẫn đọc được bằng link riêng) rồi xoá row lớp. Nút xoá thuộc về
   giáo viên nhưng nhắm vào tài liệu của nhóm.

**AC — test bắt buộc (mỗi cái là một hành vi, không phải một mã):**
- (a) `class_id` sai dạng và `class_id` đúng dạng nhưng không tồn tại trả **giống hệt
  nhau** — 404 phân biệt hai loại là đầu dò filesystem (đã vá ở P2, đừng tái nhập).
- (b) **Cũng phải đúng trên đường ghi**: giữ `write_key` của lớp A thì đổi tên được A,
  và gặp lớp B bằng **cùng hình dạng lỗi** như người lạ — đường ghi không được biến
  thành máy dò tồn tại.
- (c) `write_key` chỉ xuất hiện **đúng một lần** ở response tạo; đọc lại lớp không có nó.
- (d) `PATCH` đổi tên **không** đổi `class_id`; gửi kèm id trong body là **422**, không
  phải bị bỏ qua im lặng.
- (e) Sau `DELETE`: mỗi submission vẫn đọc được bằng id riêng, `class_id` rỗng, và
  không xuất hiện trong danh sách lớp nào.
- (f) `GET /classes/{id}` sắp `createdAt` **giảm dần**, và mọi phần tử có
  `createdAt` — xếp hàng bằng `revision` (số vòng, không phải thời gian) là sai.
- (g) `POST /submissions` với `class_id` không tồn tại → 422 nêu tên field.
- (h) Xem lại route đọc của submission: `class_id` mới **phải lộ ra** ở
  `GET /submissions/{id}` — nó là whitelist, thêm vào store mà quên route thì người
  đọc không bao giờ thấy, không lỗi, không test đỏ.
- (i) `class_id` sai dạng không đọc được file ngoài thư mục store.
- (j) Xoá lớp là **write-many**: nếu một file submission hỏng giữa chừng, các
  submission còn lại vẫn đọc được và lớp vẫn bị xoá — việc chịu lỗi phải là chủ ý,
  không phải im lặng mất dữ liệu.

**Dừng khi:** nếu ADR 0017 chưa có → quay lại WP1 (viết ADR trước, code sau).

### WP3 — Server: quyết định của giáo viên (1–2 giờ)

Không có cái này thì vòng lặp giáo viên dừng ở "đọc" — bấm Duyệt là nút chết.
**Mục này viết lại sau ADR 0017:** uỹ quyền quyết định **KHÔNG** phải app token.

**File:** `server/app/infrastructure/submissions.py` (`decide()`),
`server/app/api/submissions.py` (route), dùng lại `verify_key` đã có ở store lớp,
test mới.

- `POST /submissions/{id}/decision` — **`X-Class-Key` của lớp chứa submission đó**,
  **không phải app token**. Body: `{"decision": "approved"|"changes_requested", "note": ""}`.
  Lý do: app token là *shared secret* mà **bản app của nhóm cũng giữ** — dùng nó ở đây
  thì nhóm tự duyệt bài của chính mình. Đúng lỗ hổng ADR 0017 đã đóng cho `DELETE`;
  không được mở lại ở đường ghi này.
- Submission **chưa thuộc lớp nào** → **409** nêu lý do `not_in_class`: không có lớp
  thì không tồn tại uỹ quyền giáo viên nào, và cho qua chính là mở lại lỗ trên.
  Submission trỏ tới lớp **đã bị xoá** → 409 `class_missing`.
- Ghi vào `history` **bằng đúng cơ chế Tầng 1**: **append**, mỗi mẩu
  `{revision, at, status, event}`; `updatedAt = decidedAt = _now()` — **một lần đọc
  đồng hồ mỗi write** (gọi `_now()` nhiều lần dễ cắt ngang ranh giới giây).
- `status` là quyết định **mới nhất**; quyết định cũ vẫn nằm trong `history` (giáo viên
  đổi ý thì lịch sử không bị xoá). Chỉ dùng đúng hai từ vựng ADR 0016 câu 2 — **không
  phát minh trạng thái thứ ba**.
- View đọc là **whitelist**: `status`, `decidedAt`, `note`, `history` phải lộ ra ở
  `GET /submissions/{id}`. Không thì giáo viên thấy nút "Duyệt" trong app còn server
  thì không có gì.

**AC — test bắt buộc:**
- (a) **hình dạng từng mẩu tin** trong `history`, không đếm số mẩu (bẫn `list.extend(dict)`
  đã ăn một lần rồi).
- (b) quyết định sai giá trị → 422, không phải im lặng bỏ qua.
- (c) **`app_token` đơn thuần KHÔNG quyết được**, trả cùng hình dạng lỗi như người lạ;
  `X-Class-Key` của lớp **khác** cũng không quyết được cho lớp này.
- (d) chưa thuộc lớp → 409 `not_in_class`; lớp đã xoá → 409 `class_missing`.
- (e) quyết định lên submission của `previous_id` vẫn đọc được, lịch sử còn nguyên.
- (f) `updatedAt == decidedAt == history[-1]["at"]` — bằng chứng "một lần đọc đồng hồ".
- (g) quyết định lần hai: `status` là quyết định mới nhất, `history` **giữ cả hai**.
- (h) đọc-qua-route thấy `decidedAt` + `note`, không chỉ `status`.
- (i) id sai dạng và id không tồn tại trả **giống hệt nhau**.

**Dừng khi:** cần thêm trạng thái ngoài `approved|changes_requested` → ADR chưa xong,
quay lại hỏi. Test (c) đỏ vì bạn cho app token quyền → bạn đã mở lại đúng lỗ hổng
ADR 0017 đóng.

### WP4 — Server: activity + watermark (1–2 giờ)

Hộp thư **không phải push** — không FCM/APNs, không worker quét hộ. Đó là hộp thư
**suy biến từ sự kiện**, kéo khi mở app. Nói rõ giới hạn này trong docstring và trong
báo cáo, vì tên "notification" dễ khiến người tưởng có push thật.

- `GET /classes/{class_id}/activity` — **không cần auth** (id là credential).
- Trả về: `[{submission_id, group, event, revision, at}]` suy ra từ `history` của mọi
  submission trong lớp, sắp theo `at` **giảm dần**.
- **Không** thêm bảng `read_state` phía server: watermark là phía app
  (`(submission_id, revision)` cuối cùng đã thấy). Hệ quả đã ghi ở ADR 0016 câu 4.
- **Lần mở app đầu tiên không được báo "có 12 thông báo mới"** — đó là hành vi sai
  dễ sa vào một test mà chỉ kiểm "danh sách không rỗng". Test phải phân biệt
  "chưa từng thấy" với "đã thấy rồi, có cái mới".

**AC:** (a) sau khi một nhóm nộp mới, activity có **đúng một** mục mới; (b) sau khi
nhóm nộp vòng 2, activity có mục mới **khác** mục cũ (không phải cùng một mục bị ghi
đè); (c) thứ tự giảm dần theo `at` với dữ liệu tự dựng có thứ tự ngược.


### WP5 — App: ba màn hình giáo viên (1–2 ngày) — **rủi ro cao nhất của plan**

**Trạng thái (2026-09-28): ĐÃ XONG** — 3 commit: 95af468 (ApiException.detail + PATCH + X-Class-Key, đăng ký seam openTeacherStore), d1953b1 (feature `features/teacher/` + wiring providers/router), 7df2101 (test 390×844). Số đo: app 968/968 · analyze/format sạch · guardrails 8/8 (696 file). Width đo được: Tạo lớp 146,7 px (nhãn 98,7) · Duyệt bài 192,9 px (nhãn 126,9) · Yêu cầu sửa 203,1 px (nhãn 155,1) · chip trạng thái 94,5 px. Hai bug lộ khi đo: AppBar title Row tràn **242 px** ở 390 (sửa thành Text + actions) và POST quyết định thiếu `X-Class-Key` (test bắt, vá cả verb).

**Ghi chú từ WP2 (đã chốt):** `DELETE /classes/{id}` trả kèm số `unfiled` và danh sách `dangling`. Màn hình lớp **hiện một dòng cảnh báo** khi `unfiled` khác 0 — nhẹ, không modal, và im lặng khi mọi thứ bình thường.

**Ghi chú từ WP3 (đã chốt):** hai lý do 409 của `POST /submissions/{id}/decision` hiện thành **hai message khác nhau**, mỗi cái một dòng, không modal: `not_in_class` — “Bài này chưa được gán vào lớp nào” (hành động: vào lớp, gán bài); `class_missing` — “Lớp không còn tồn tại, hoặc khoá nhập không đúng” (hành động: tạo lại lớp / nhập lại khoá). Message thứ hai **giữ nguyên sự mơ hồ** “thiếu lớp *hoặc* sai khoá” — tách thành hai lý do riêng là biến đường ghi thành máy dò tồn tại, đúng thứ ADR 0017 đã đóng.

Đây là chỗ plan này dễ hỏng nhất, và lý do không phải logic: **toàn bộ test UI hiện
tại ngồi ở desktop** (`app/test/desktop/`, `app_breakpoint_test.dart` đo 9 bề rộng).
Plan này dời trọng tâm sang **điện thoại**, nghĩa là vào vùng chưa từng có ai đo.

**Cấu trúc (mirror `app/lib/features/workspace/`, đừng phát minh layout mới):**
- Thư mục mới `app/lib/features/teacher/` với `view/` + view-model theo **đúng cách
  repo đang đặt file** (hiện chỉ có `features/workspace/` — copy khuôn đó).
- Ba màn hình: **inbox lớp** (danh sách lớp, sắp theo thời gian) → **lớp** (activity +
  trạng thái từng submission) → **một submission** (đọc report + Duyệt / Yêu cầu sửa).
- **Shell:** `app/lib/core/router/app_router.dart` hiện **không nhận tham số** và trả
  về đúng một `WorkspaceShell`. Đổi thành
  `buildRouter({AppRoleScope scope = const AppRoleScope.student()})` — **có giá trị
  mặc định**, vì thêm tham số bắt buộc sẽ phá mọi call site và mọi test đang gọi nó
  (bẫy đã ghi trong `AGENTS.md`). Với `scope.role == AppRole.teacher` thì trả teacher shell.

**Bốn luật, mỗi luật gắn với một lỗi đã xảy ra ở đúng chỗ này:**

1. **Không điều hướng bằng path literal.** Đã có bug: nút Open gọi
   `context.go('/workspace')` trong khi tab hiện tại có path `/` ⇒ `GoException` **sau khi
   việc thật đã xong**, màn hình đứng yên trông như "mở lỗi". Chuyển tab bằng
   `StatefulNavigationShell.of(context).goBranch(i)` như rail/tab bar đang làm.
   Hồi quy tồn tại: `app/test/review_history_route_test.dart`.
2. **`AppPlatform` không được đổi một chữ.** ADR 0015 đã có test giữ lời hứa. Muốn
   khác layout theo vai trò thì đọc `AppRole` + `MediaQuery`, **không** đọc nền tảng.
3. **Mọi màn hình phải có test ở 390×844 và test phải ĐO KÍCH THƯỚC.**
   Đặt `tester.view.physicalSize` + `devicePixelRatio = 1`, rồi
   `tester.getSize(<nút>).width` so với bề rộng nhãn. **"0 lỗi overflow" KHÔNG đồng
   nghĩa "không bị cắt"** — đã đo được một nút còn **28.2 px** ở 390, nhỏ hơn padding
   30 px của `WButton`, nhãn bị `ellipsis` mất sạch, và **không** dựng
   `RenderFlex overflowed` nào nên audit đếm overflow không thấy. Hàng nút dùng
   **`Wrap`**, không `Row` + `Expanded`. Sau khi đổi sang `Wrap`: 28.2 px → 224.3 px.
4. **Test phải đo trên dữ liệu đã chấm.** Đo trang Báo cáo trên container *chưa* chấm
   thì chip toàn số `0`, hẹp, không tràn — xanh mà **không chứng minh gì**. Phải
   `loadDemo()` + `runReview()` trước khi đi tới trang.

**Hai điều phải nói to trong UI, không được giấu:**
- Báo cáo giáo viên xem phải mang cờ **"điểm chưa được kiểm định"** (chưa có gold set —
  xem WP7). Không trình như án tại hồ sơ.
- Hộp thư là **hộp thư kéo khi mở app**, không phải push. Watermark "đã đọc" là của
  **máy này**. Chữ trên UI phải nói đúng điều đó.

**Luật kỹ thuật còn lại:** gọi server qua `ApiService` + repository sẵn có (luật
guardrail: app không gọi thẳng LLM); nếu thêm provider mới thì **override về `null` mặc
định trong harness test** và giữ `ref.read` trong `try` — hai lỗi này đã làm nổ test
không liên quan. Widget mới có import plugin native thì phải đăng ký kèm seam trong
`tools/check_guardrails.py`, **không thêm ngoại lệ**.

**AC:** (a) mỗi màn hình một test 390×844 **có in số đo width** trong tên hoặc comment
test — test xanh mà không số đo là test chưa đo gì; (b) `app_role_test.dart` vẫn xanh;
(c) `review_history_route_test.dart` vẫn xanh; (d) `flutter analyze --fatal-infos
--fatal-warnings` sạch; (e) `dart format` không đổi file.
**Dừng khi:** nếu `flutter test` đỏ ở test **không liên quan** sau khi bạn thêm
provider mới → dừng sửa, đọc lại bẫy số 8 ở §1 thay vì vá từng test.


### WP6 — Đo chain 1 trên OTES thật (đóng AC4 của plan 10)

**Trạng thái (2026-09-28): XONG, kết quả 0** — test đo `app/test/chain1_otes_real_document_test.dart` chạy pipeline của app trên text OTES 217 trang (fitz, `%TEMP%\otes_pages.json`): parser **1.4.4**, **91 unit** (63/63 UC; hồ sơ 130 là của 1.4.2), **chain 1 = 0 finding** — 0 thật có chẩn đoán: 91/91 unit đều trích được entity, chỉ 1 cluster đạt ≥2 mục (stem `we`, 1 original) nên bị cổng ≥2-originals chặn đúng; văn OTES không có hình dạng hai-nhãn-một-khái-niệm mà check bắt. Bằng chứng + lệnh tái chạy: `docs/evidence/chain1-otes-2026-09-28.md`. 0 call LLM, không đụng `.env`, app **969/969**.

`docs/plans/10` §0 nói thẳng: AC4 *"số finding chain 1 trên OTES > 0"* mới chỉ được
chứng minh bằng dữ liệu **tự dựng**, **chưa lần nào** đưa text OTES thật vào
`ContradictionPass`. Đây là gate M2.

- **Điều kiện tiên quyết cần hỏi người:** file OTES (≈28,7 MB) **không nằm trong
  git** — phải định vị hoặc xin đường dẫn. Không có file thì **báo chặn, dừng WP6**,
  đừng tạo tài liệu thay thế.
- Chạy review thật (`mock_mode` **tắt**) trên server **tự host**, rồi đưa `pageTexts`
  qua `ContradictionPass` và **đếm finding chain 1**.
- Chi phí: nhờ pacing + batch (ADR 0010), một lượt ≈ 40 call thay vì 1347. **Hỏi ý
  kiến người trước khi tiêu quota** — quota là 50 request/ngày/người.
- Ghi `docs/evidence/chain1-otes-<ngày>.md`: số trước/sau, cách đếm, và **kết quả kể
  cả khi bằng 0**. AC-10.2 của plan 10 nói thẳng điều này: bằng 0 cũng là bằng chứng,
  giấu đi là bịa.

**AC:** có file evidence với **số** (kể cả 0) + cách tái chạy lệnh đó.
**Dừng khi:** thiếu file OTES, hoặc chưa được duyệt chi phí → ghi vào báo cáo là
`blocked`, tuyệt đối không chạy bằng `mock_mode` rồi ghi như số thật.

### WP7 — Gold set: dựng **bộ dụng cụ**, KHÔNG tự tạo gold

**Trạng thái sau phần 2 (2026-09-27):** nguồn mẫu **đã có** và **đã nối vào bộ dụng cụ** —
`reviews/workspace-snapshot-2026-09-22-parser1.4.1.json`, **240 unit**, phân bố
`Section` 168 · `Use case` 61 · `Functional` 5 · `Non-functional` 4 · `Unknown` 2; file là
dump của `shared_preferences` nên giá trị bị **mã hoá hai lớp**, và loader **không hardcode
tên key** (key nào parse ra object có `units` là mảng thì nhận). Bộ dụng cụ **chạy được
end-to-end trên nguồn thật** (48 test, gồm 4 test đọc chính file đó). **Thứ còn thiếu chỉ là
hai người ký.** Cảnh báo phạm vi: nguồn chạy trên parser **1.4.1** nên chỉ dùng để chấm
**tiêu chí trên từng unit**, **không** dùng để kết luận về phân đoạn unit (đọc
`docs/evidence/goldset-instrument-2026-09-27.md` mục 1).

**Sự thật phải nói trước khi làm:** gold set là nơi người khác tự chấm; người tự dán
rồi tự chấm thì đó là **gold set vô giá trị** (plan 10 §3 ghi nguyên văn). Nên WP này
**không thể hoàn thành một mình** — và bạn **không được giả vờ hoàn thành**.

Cái bạn làm được và **có giá trị thật** là bộ dụng cụ, để khi có hai người ngồi ký
thì việc đo chạy được ngay:

1. **Script lấy mẫu:** rút N unit **phân tầng** (có `Main flow` / NFR viết thành văn /
   UC trùng ID — vì OTES trùng ID có hệ thống), xuất ra sheet annotation.
2. **Sheet annotation** (CSV hoặc markdown) với **đúng trường** cần đo, và **một cột
   `annotator`** — không có cột này thì không tính được độ khớp giữa hai người.
3. **Script độ khớp giữa hai người**, ngưỡng **≥ 80%** theo plan 10 §3.
4. **Script precision/recall**, chỉ chạy được khi có **hai** sheet khác người.
5. **Test âm (quan trọng nhất):** bộ dụng cụ phải **báo "chưa đủ tin cậy"** khi độ khớp
   dưới 80%. Dùng hai sheet mẫu tự dựng lệch nhau để chứng minh điều đó — một bộ
   dụng cụ chỉ biết nói "đạt" là bộ dụng cụ vô dụng.

**AC:** script chạy được end-to-end trên dữ liệu mẫu tự dựng; trường của sheet được
ghi rõ; có test âm chứng minh ngưỡng 80% **thật sự chặn**.
**Dừng khi:** đừng viết file evidence kiểu "gold set đạt" — hãy viết
`docs/evidence/goldset-instrument-<ngày>.md` nói rõ **còn thiếu hai người ký**, và
**còn chưa có** số precision/recall.

### WP8 — Ba gate M5 (cần khóa API thật + người duyệt)

**Trạng thái (2026-09-29): gate 2 XONG, gate 1 chạy thật được, gate 3 mở nửa** —
gate 2: **10/10 trích dẫn trong báo cáo OTES là thật**, nhãn "khớp nguyên văn" mới là cái
quá mạnh (bằng chứng: `docs/evidence/citation-crosscheck-otes-2026-09-28.md`). Gate 1:
lượt E2E **91/91 unit, 0 fail** (242,3 s, 12 cache hit → 79 chấm thật; server trả
**122 findings đã verify** — con số `findings=0` của driver là lỗi đếm, chênh lệch với
report 232 được quy kết thành 232 vs 122: khác mẫu số + prompt đổi;
`docs/evidence/finding-gap-232-vs-0-2026-09-29.md`); đường sơ đồ vẫn
chưa được chứng minh — `docs/evidence/e2e-llm-path-otes-2026-09-29.md`). Gate 3: HisWise
SDS có file thật trong `server/`, harness dump unit qua parser 1.4.4 đã có
(`app/test/hiswise_units_dump_test.dart`, **7 unit/16 trang**); **CarbonX thiếu file gốc**
— holdout vẫn cần người duyệt chi phí trước khi chấm lại.

Từ `docs/roadmap.md` M5, còn thiếu:
1. **E2E desktop chạy LLM path thật** — sign-off 09-14 ghi rõ **không đo lại LLM path**
   sau 2026-09-21. Đây là gap lớn nhất về niềm tin.
2. **Đối chiếu thẳng 10 citations** trong báo cáo.
3. **Holdout ngữ nghĩa** — CarbonX/HisWise đã chạy thật (`reviews/`, 2026-09-15) nhưng
   **trước khi luật mới có**, nên chưa chứng minh thang điểm có giữ được ổn định.

**Luật bất di bất dịch:** gate nào cần tiền thật thì **dừng và hỏi**, ghi rõ ước tính
chi phí trước khi chạy. Một con số tốt đẹp mà tốn hết quota người dùng là việc làm
tệ hơn cả làm nửa.


---

## 3. Ma trận nghiệm thu (đánh dấu được, không tự khen)

| # | Tiêu chí | Bằng chứng phải có |
|---|---|---|
| AC-12.1 | Cây làm việc sạch, commit theo lớp | `git status` không còn rác; roadmap có số đo kèm ngày |
| AC-12.2 | 3 suite xanh **sau khi commit** | app, server, guardrails, exit 0 |
| AC-12.3 | ADR 0016 trả lời 4 câu tường minh | tìm `revocation`, `self-hosted` đều ra câu trả lời |
| AC-12.4 | Hai loại 404 giống hệt nhau | test khẳng định **bằng chứng bằng nhau**, không phải "cùng status" |
| AC-12.5 | Field mới nhìn thấy được qua route | test đọc-qua-route, không test store |
| AC-12.6 | Lịch sử đúng **hình dạng từng mẩu tin** | test khẳng định dict, không đếm số mẩu |
| AC-12.7 | Màn hình giáo viên đo được ở 390×844 | test **có số đo width**, không chỉ "không overflow" |
| AC-12.8 | `AppPlatform` không đổi | `app_role_test.dart` xanh |
| AC-12.9 | Báo cáo giáo viên ghi rõ chưa kiểm định | có dòng cảnh báo trên UI, có test |
| AC-12.10 | Guardrails 8/8 | chạy `tools/check_guardrails.py` |
| AC-12.11 | Format/analyze sạch | `dart format --output=none --set-exit-if-changed .` + `flutter analyze --fatal-infos --fatal-warnings` |
| AC-12.12 | AC4 đo trên tài liệu thật | **Đạt phần đo** — evidence có số **0** kèm chẩn đoán; tiêu chí "> 0" của plan 10 **đã sửa** vì tài liệu không có hình dạng dữ liệu mà check nhắm tới (`chain1-otes-2026-09-28.md`) |
| AC-12.13 | Bộ dụng cụ gold set **có test âm** | chứng minh ngưỡng 80% thật sự chặn |

**Kết quả rà ma trận (2026-09-29, HEAD `f0f4f8b`) — 11 ĐẠT · 1 ĐẠT-PHẦN · 1 CHƯA; không ô nào được lấp số:**

| # | Trạng thái | Bằng chứng hiện có |
|---|---|---|
| AC-12.1 | ĐẠT | `git status` sạch; commit theo lớp (WP5/6/8 tách feature/test/docs, `f0f4f8b` là style riêng); roadmap có số đo kèm ngày (M5 + test estate 2026-09-29) |
| AC-12.2 | ĐẠT | đo **sau** commit `f0f4f8b`: app 971/971 · server 350 passed + 1 skipped · guardrails 8/8 (706 file) |
| AC-12.3 | ĐẠT | `docs/adr/0016` — `revocation` → §Decision 1 ("there is no revocation", dòng 59); `self-hosted` → §Decision 3 (dòng 68) |
| AC-12.4 | ĐẠT | `server/tests/test_submissions.py::test_unknown_id_is_404_identical_to_malformed` — assert cả body (`unknown.json() == malformed.json()`) chứ không chỉ status; cùng mẫu ở `test_classes.py`, `test_decisions.py`, `test_activity.py` |
| AC-12.5 | ĐẠT | `test_submission_time.py::test_read_route_exposes_the_time_the_writer_recorded` (dòng 91) — đọc qua route, không qua store |
| AC-12.6 | ĐẠT | `test_decisions.py` :78/:239/:286 — assert nguyên bộ key `{revision, at, status, event}` của từng mẩu history, không đếm số mẩu |
| AC-12.7 | ĐẠT | `app/test/teacher_screens_phone_test.dart` in `MEASURED [...]` (:318, :409): Tạo lớp 146,7 px (nhãn 98,7) · Duyệt bài 192,9 (126,9) · Yêu cầu sửa 203,1 (155,1) · chip 94,5 px — ở 390×844 |
| AC-12.8 | ĐẠT | `app/test/app_role_test.dart` xanh trong 971/971 |
| AC-12.9 | ĐẠT | UI: `teacher_submission_view.dart` :280 "Điểm này CHƯA được kiểm định…"; test: `teacher_screens_phone_test.dart` :447–448 (`findsOneWidget` + `textContaining('CHƯA được kiểm định')`) |
| AC-12.10 | ĐẠT | `python tools/check_guardrails.py` — 8/8 nhóm, 706 file (đo 2026-09-29 sau `f0f4f8b`) |
| AC-12.11 | ĐẠT | `dart format --output=none --set-exit-if-changed .` exit 0 **toàn cây** (sau khi format `wp8_phase0_call_cost_test.dart` — `f0f4f8b`) + `flutter analyze --fatal-infos --fatal-warnings` "No issues found" |
| AC-12.12 | ĐẠT-PHẦN (đúng chữ tiêu chí) | evidence có số **0** kèm chẩn đoán: `chain1-otes-2026-09-28.md`; **ADR-0018** chốt vì sao 0 là phạm vi designed (unit văn xuôi ≠ dòng dictionary; nới cần gold set); test tái lập `chain1_otes_real_document_test.dart` — phần chưa đạt là phía "> 0" của plan 10, vì tài liệu không có hình dạng dữ liệu mà check nhắm tới |
| AC-12.13 | CHƯA | 48 test bộ dụng cụ chạy được + test âm khẳng định ngưỡng 80% chặn (`test_goldset_instrument.py` `TestAgreement`); **còn thiếu hai người ký** và **chưa có precision/recall** — `goldset-instrument-2026-09-27.md` ghi đúng điều đó |

Mốc "hết việc" của plan (12.1→12.3, 12.6→12.11 xanh): **đạt**. Hai ô còn mở là kết quả hợp lệ theo §3 — không bịa số lấp ô: AC-12.12 thiếu "> 0" vì tài liệu không có hình dạng dữ liệu (ADR-0018); AC-12.13 thiếu hai người ký (việc của người, không phải của agent).

**Mốc "hết việc" của toàn plan:** AC-12.1 → 12.3, 12.6, 12.7, 12.8, 12.9, 12.10, 12.11
xanh. **AC-12.12 và 12.13 có thể phải ghi `blocked`** kèm lý do — đó là kết quả hợp lệ,
không phải thất bại, **miễn là bạn không bịa số để lấp ô trống**.

## 4. Danh sách cấm (đã có người trả giá, đừng thử lại)

1. **Không tự tạo gold set** rồi tự chấm. Đây là cách nhanh nhất để có một repo trông
   như có kiểm định mà thực ra không có gì được kiểm định.
2. **Không nâng finding lên thang điểm khi chưa có gold set.** `requiresVisionEvidence`
   giữ nguyên; verdict **không** cộng chain 2/3 (AC-10.6).
3. **Không thêm provider mới** (đã có ADR 0008 vì sao không thêm KiraAI) và **không
   bỏ qua pacer**: mọi call upstream phải qua `ProviderPacer`. Thêm
   `provider.generate_json` ở chỗ khác mà quên `acquire` là tái tạo đúng cơn retry
   storm (1347 call cho 238 unit).
4. **Không nâng trần 40 unit/lượt.** Đó là quyết định thiết kế, không phải bug: quota
   50/ngày, kẹp 40 giữ 10 request dự phòng.
5. **Không hồi sinh snapshot** (`srs.workspace.snapshot`): đã bỏ có chủ đích; draft
   nhỏ chỉ giữ projectName/projectInfo/humanIssues.
6. **Không nhét units/findings/result vào draft** — chúng thuộc về session.
7. **Không sửa `AppPlatform`**, không thêm bottom sheet (ADR 0014), không thêm ngoại lệ
   guardrail.
8. **Không nâng `context_text` `/diagram` quá 4000 ký tự** mà không tự cap.
9. **Không nói một nhận định về hình sơ đồ là đã kiểm chứng** — model không đọc được
   ảnh trong phiên harness.
10. **Không dùng `path literal` để chuyển tab** (bẫy `GoException` ở Lịch sử).

## 5. Báo cáo cuối — đúng định dạng này, không hơn

```md
# Báo cáo chạy plan 12 — <ngày>

## Đã làm
- WPn: <một dòng kết quả> — bằng chứng: <file:line hoặc số đo>

## Số đo (đo lúc chạy, không sao chép từ plan)
- app: <n> pass
- server: <n> pass, <n> skip
- guardrails: <k>/<n> nhóm, <n> file

## Chặn / chưa làm
- <việc> — vì sao chặn, cần gì để mở

## Rủi ro / nợ để lại
- <một dòng, kèm nơi ghi>

## Câu hỏi cần người quyết
- <câu hỏi cụ thể, có lựa chọn>
```

**Cấm trong báo cáo:** số liệu không kèm lệnh đã chạy; "đã xong" cho WP nào chưa có
test; ước tính chi phí ghi như đã tiêu; và bất kỳ khẳng định nào về độ chính xác khi
chưa có gold set.

## 6. Thứ tự chạy (chép lại, đừng nhảy cóc)

```text
WP0 dọn+commit
  └─ WP1 ADR 0016
       └─ WP2 lớp (roster)  ──┬─ WP3 quyết định giáo viên ─┐
                               └─ WP4 activity + watermark ─┴─ WP5 app (3 màn, 390px)
WP6 đo chain 1 trên OTES   (cần file thật + duyệt quota, độc lập WP2-5)
WP7 bộ dụng cụ gold set     (cần hai người ký; bạn chỉ làm được phần dụng cụ)
WP8 ba gate M5              (cần khóa API thật + người duyệt chi phí)
```

**Có thể làm song song nếu máy đủ:** WP1↔WP6, và WP7 sau WP6. **Không** làm song
song WP2–WP4 với WP5: app sẽ phải sửa lại khi API đổi, và bạn sẽ có hai lần viết
cùng một màn hình.

## 7. Prompt giao việc

Prompt sẵn sàng để **copy-paste** cho model mới nằm ở file riêng:
`docs/plans/12-handoff-prompt.md` — dùng nó, đừng tự viết lại prompt: nó đã gói sẵn
§0, §1, điều kiện dừng và định dạng báo cáo, và có **hai chế độ** (chạy hết từ WP0,
hoặc chạy một WP đã chỉ định).

