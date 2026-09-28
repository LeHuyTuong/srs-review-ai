# Prompt giao việc — chạy plan 12

Đây là **prompt sẵn sàng copy-paste** để gửi kèm repo cho một model khác. Chọn **đúng
một** khối bên dưới, dán nguyên văn — đừng tự viết lại: các khối đã gói sẵn điều
kiện dừng, luật cấm, và định dạng báo cáo.

Cách dùng: gửi cho model **repo** (hoặc bản clone / archive của repo) **kèm** prompt
này. Không cần kèm hội thoại cũ — prompt tự chứa đủ phần còn thiếu.

---

## Chế độ A — chạy hết từ đầu (khuyến nghị)

````markdown
Bạn là kỹ sư phần mềm tiếp quản repo `srs-review-ai` (app Flutter + server FastAPI) tại
đường dẫn workspace hiện tại. Bạn KHÔNG có hội thoại trước đó. Nhiệm vụ: chạy phần
việc còn lại của roadmap theo kế hoạch đã có sẵn trong repo.

# Bước 0 — ĐỌC, chưa sửa gì
1. Đọc `AGENTS.md` ở gốc repo, toàn bộ. Đó là luật của dự án và là danh sách những
   bẫy đã bị ăn tiền. Không đọc thì bạn sẽ tái tạo bug đã sửa.
2. Đọc `docs/plans/12-run-everything-remaining-2026-09-27.md`, toàn bộ. Đó là kế
   hoạch bạn thực thi (WP0 → WP8, tiêu chí nghiệm thu AC-12.*, điều kiện dừng, và
   định dạng báo cáo).
3. Đọc tiếp `docs/plans/11-teacher-app-2026-09-27.md` và `docs/adr/README.md` +
   ADR 0010/0011/0014/0015. Trong đó, ADR 0015 là lý do không được sửa `AppPlatform`.

# Bước 1 — ĐO nền tảng, đừng tin số của ai
Chạy đúng ba lệnh này (Windows; trên macOS/Linux dùng `server/.venv/bin/python`):
  cd server && .venv\Scripts\python.exe -m pytest tests -q
  cd app    && flutter test
  python tools\check_guardrails.py
Ghi lại kết quả thật của bạn. Mốc tham chiếu ghi trong plan (app 946, server 238,
guardrails 8/8) chỉ để so; nếu lệch, ĐỪNG sửa code để khớp — hãy điều tra và báo.

# Bước 2 — Thực thi theo thứ tự phụ thuộc
Làm lần lượt WP0, WP1, WP2, WP3, WP4, WP5. Mỗi WP chỉ coi là xong khi:
  - mọi tiêu chí AC tương ứng của nó có bằng chứng cụ thể (tên test / số đo), và
  - cả ba lệnh ở Bước 1 vẫn xanh.
WP6, WP7, WP8 phụ thuộc dữ liệu thật và người thật — xem "Điều kiện dừng" bên dưới.
Không gộp nhiều WP vào một lần sửa lớn: mỗi WP một commit hoặc một nhóm commit
nhỏ, đọc nổi.

# Luật kỹ thuật bắt buộc (rút từ AGENTS.md, phần dễ sai nhất)
- `pytest` chỉ có trong `server/.venv`. `python3 -m pytest` luôn báo thiếu module;
  kết luận "test hỏng" từ lệnh đó là chẩn đoán sai.
- `ruff` không cài trên máy này nhưng CI chạy `ruff check .` và `ruff format --check .`.
  Không cài, để CI phản hồi.
- Trước khi commit app: `dart format .` rồi `flutter analyze --fatal-infos
  --fatal-warnings`. CI kiểm tra cả hai.
- File `.py` trong `server/` dùng CRLF. Sửa nhiều dòng bằng script Python đọc/ghi với
  `newline=""`, chuẩn hoá rồi khôi phục kiểu cũ; luôn đọc lại file sau khi vá.
- Mọi call vào plugin native phải có probe hoặc fake. Import plugin native ở file
  mới phải được đăng ký kèm seam trong `tools/check_guardrails.py` — không thêm ngoại lệ.
- `ref.read(provider)` trong view-model phải nằm trong `try`; provider mới phải được
  override về null trong harness test.
- Khi đo lỗi UI: bơm hết hàng đợi exception
  (`while ((e = tester.takeException()) != null)`), và **đo kích thước** chứ đừng chỉ
  đếm overflow: một `Expanded` bị bóp cạn không dựng exception nào, đã có nút còn
  28.2 px ở bề rộng 390 khiến nhãn bị cắt sạch mà audit vẫn báo "0 lỗi".

# Điều kiện dừng — DỪNG VÀ HỎI, đừng tự quyết
- Cần tiêu tiền/quota (mọi lượt chấm thật có key Gemini; quota 50 request/ngày/người).
- Cần xoá hoặc commit một file bạn không chắm bắt nguồn gốc (ví dụ file media lạ ở
  gốc repo).
- Một câu hỏi thiết kế trong ADR 0016 chưa có câu trả lời.
- Sửa của bạn làm đỏ test không liên quan mà bạn chưa hiểu nguyên nhân.

# Cấm (đều đã có người trả giá)
- Tự tạo gold set rồi tự chấm. Chỉ dựng bộ dụng cụ, và phải có test âm chứng minh
  ngưỡng khớp thật sự chặn.
- Nâng finding lên thang điểm khi chưa có gold set; verdict không cộng chain 2/3.
- Thêm provider mới, hoặc gọi `provider.generate_json` mà không qua `ProviderPacer`.
- Nâng trần 40 unit/lượt, hồi sinh snapshot, nhét units/findings vào draft.
- Sửa `AppPlatform`, thêm bottom sheet, thêm ngoại lệ guardrail.
- Dùng path literal để chuyển tab (đã gây `GoException` sau khi việc thật đã xong).
- Khẳng định bất kỳ điều gì về hình sơ đồ UML là "đã kiểm chứng" — bạn không đọc được
  ảnh trong phiên làm việc này.

# Báo cáo cuối
Theo đúng mẫu trong `docs/plans/12-run-everything-remaining-2026-09-27.md` §5: việc
đã làm kèm bằng chứng, số đo đo lúc chạy, phần chặn kèm lý do, nợ để lại, và câu
hỏi cần quyết. Không có số nào mà không kèm lệnh đã chạy. "Đã xong" chỉ dùng cho
WP nào thật sự có test.
````

---

## Chế độ B — chỉ chạy một WP đã chỉ định

Dùng khi bạn muốn chia nhỏ, hoặc muốn model mới làm tiếp từ một điểm. Thay
`WP<n>` bằng số thật.

````markdown
Bạn tiếp quản repo `srs-review-ai`. Nhiệm vụ hẹn: **chỉ** làm WP<n> của
`docs/plans/12-run-everything-remaining-2026-09-27.md`. Không làm WP nào khác, kể cả
khi thấy chúng "rõ ràng là cần làm" — nếu WP<n> bị chặn bởi WP trước thì báo chặn và
dừng, đừng nhảy cóc.

Đọc trước khi sửa: `AGENTS.md` (toàn bộ), rồi plan 12 §0, §1, §2 (phần WP<n>),
§3, §4, §5. Sau đó:

1. Chạy ba lệnh nền ở plan §0 và ghi kết quả thật. Nếu chúng **đang đỏ trước khi bạn
   bắt đầu**, dừng và báo — đó không phải lỗi của WP<n>.
2. Làm đúng phạm vi WP<n>. Nếu phát hiện lỗi ngoài phạm vi, **ghi lại trong báo cáo**,
   đừng sửa.
3. Hoàn thành khi: AC của WP<n> có bằng chứng (tên test hoặc số đo), và ba lệnh nền
   vẫn xanh, và `git status` cho thấy thay đổi gọn (không kéo theo file rác).
4. Báo cáo theo plan §5, ngắn gọn, có số đo kèm lệnh đã chạy. Nêu rõ điều kiện dừng
   nào (nếu có) đã kích hoạt.
````

## Chế độ C — chỉ dọn và commit (bước an toàn trước khi giao tiếp)

Hữu ích nếu bạn muốn có một mốc sạch trước khi cho model khác đụng vào: cây làm việc
hiện có nhiều thay đổi chưa commit. Chạy đúng WP0, rồi dừng.

````markdown
Bạn tiếp quản repo `srs-review-ai`. Nhiệm vụ hẹn: **chỉ** làm WP0 (dọn cây làm việc và
commit theo lớp) của `docs/plans/12-run-everything-remaining-2026-09-27.md`, rồi dừng.

Đọc `AGENTS.md` và plan 12 §0, §1, §2 (WP0), §5 trước khi làm.

1. Chạy ba lệnh nền ở plan §0, ghi kết quả thật.
2. Chia commit thành 4 nhóm có nghĩa đúng như WP0 mô tả (app-vision, server-submissions,
   docs, app-role). Không chia nhỏ hơn mức đó và không gộp tất cả vào một commit.
3. Xoá rác đã liệt kê trong WP0. **Không** xoá file `.mp4` ở gốc repo và **không** quyết
   định thay người dùng về `app/run.bat` / `server/run_server.bat` — hỏi trước.
4. Thêm `.gitignore` cho cache sinh ra lúc chạy và file `.out.txt`, dùng pattern cụ thể.
5. Sửa dòng "Test estate" trong `docs/roadmap.md` bằng **số bạn vừa đo** kèm ngày.
6. Chạy lại ba lệnh nền **sau khi commit** để chứng minh không bỏ sót file. Báo cáo
   theo plan §5, nêu rõ commit nào chứa gì.
````

## Đóng gói repo để gửi (làm trước khi dán prompt)

| Cách | Đánh giá |
|---|---|
| **Push nhánh rồi gửi link + prompt** | Đúng nhất. `.env` đã nằm trong `.gitignore` và **không** được git theo dõi (đã kiểm: `git ls-files` không có file `.env`), nên kẻ nhận không thấy khoá Gemini. |
| **Copy nguyên thư mục** | **Cẩn thận:** `server/.env` có thật trên đĩa — copy tay là **mất khoá**. Thư mục cũng nặng ~393 MB (đã trừ `.git`/`.venv`/`build`/`.dart_tool`). |
| **Bundle git** | `git bundle create srs-review-ai.bundle --all` — gọn nhất, không kèm file untracked. |

**Không cần gửi kèm:** `docs/plans/12-*.md` và prompt này **đã nằm trong repo**; hãy chỉ
dán phần prompt vào tin nhắn. Không gửi `server/.env`, không gửi file SRS gốc (OTES
≈28,7 MB, cũng không nằm trong git), không gửi `.mp4` lạ ở gốc repo.


---

## Chế độ D — chạy ngay trong session đang mở (dành cho chính bạn)

Session này đã có đủ bối cảnh: plan 11/12 vừa viết, Tầng 1 server đã làm xong và xanh,
ba bẫy mới (CRLF, `extend(dict)`, route whitelist) vừa dính tay nên đã thuộc. Vì vậy
prompt này **ngắn**: chỉ việc trỏ tới plan và siết hành vi. Không dùng lại Chế độ A ở
đây — bản đó viết cho model chạy lạnh.

````markdown
Chạy `docs/plans/12-run-everything-remaining-2026-09-27.md` từ WP0 theo thứ tự phụ
thuộc, mỗi WP một lần báo cáo riêng.

Các điều đã đo trong session này, đừng đo lại vô ích: app 946/946, server 238 (1 skip),
guardrails 8/8 — nhưng vẫn chạy lại 3 lệnh nền **một lần** ở đầu, và chạy lại sau
mỗi WP để chứng minh không phá gì. Số lệch mốc thì báo, không sửa code cho khớp.

Tại mỗi WP: làm đúng phạm vi, dừng khi đủ AC của WP đó, rồi báo cáo ngắn (đã làm /
số đo kèm lệnh / chặn / câu hỏi cần tôi quyết) và **chờ tôi nói tiếp** trước khi sang
WP kế tiếp. Không gộp nhiều WP vào một lần sửa.

Dừng hỏi tôi, đừng tự quyết: cần tiền/quota Gemini; cần xoá hoặc commit file không
chắm nguồn gốc (`.mp4` lạ, hai file `.bat`); một câu trong ADR 0016 chưa có câu trả lời;
sửa làm đỏ test không liên quan mà bạn chưa hiểu nguyên nhân.

Cấm: tự tạo gold set rồi tự chấm (WP7 chỉ làm bộ dụng cụ, phải có test âm chứng minh
ngưỡng 80% thật sự chặn); nâng finding lên thang điểm khi chưa có gold; bỏ qua
`ProviderPacer`; nâng trần 40 unit/lượt; hồi sinh snapshot; sửa `AppPlatform`; thêm
bottom sheet; thêm ngoại lệ guardrail; dùng path literal để chuyển tab; khẳng định
điều gì về sơ đồ UML là "đã kiểm chứng".

Với WP5 (app giáo viên): mỗi màn hình một test 390×844 **có in số đo width** — đo
trên dữ liệu đã chấm (`loadDemo()` + `runReview()`), dùng `Wrap` không dùng
`Row`+`Expanded`. "0 lỗi overflow" không phải bằng chứng không bị cắt.

WP6 (đo chain 1 trên OTES) cần file OTES thật + tôi duyệt chi phí; thiếu thì ghi
`blocked`. WP8 cần tôi duyệt chi phí. Không tự chạy lệnh tốn tiền.
````


---

## Chế độ E — chạy tiếp từ chỗ đang dừng (dành cho chính bạn)

Dùng chế độ này khi bạn vừa làm xong một WP và muốn nhảy sang WP kế tiếp mà
không cần đọc lại cả plan. Cập nhật các số trong **ngoặc** trước khi dán.

````markdown
Tiếp tục plan 12. Trạng thái đã đo trong session này:

- Đã xong: WP0 (dọn + commit 7 lớp), WP1 (ADR 0016), và ADR 0017 (lớp là full CRUD,
  write key riêng, membership nằm trên submission, DELETE không xoá bài nhóm).
- Số đo chốt: app 946/946 · server 238 collected, exit 0, 1 skip · guardrails 8/8, 676 file.
- `git status` sạch, commit mới nhất `2a1fdd5`.

Bây giờ làm **WP2** — server: lớp học (roster), full CRUD. Nguồn chuẩn là
`docs/plans/12-run-everything-remaining-2026-09-27.md` §2 WP2 và
`docs/adr/0017-class-crud-and-write-key.md`. Đọc cả hai trước khi viết dòng code đầu
tiên, cùng `server/app/infrastructure/submissions.py` để bám khuôn store sẵn có.

Cần tạo/sửa: `server/app/infrastructure/classes.py` (mới), `server/app/api/classes.py`
(mới), wire store trong `main.py` → getter trong `deps.py` **+ thêm tên vào `__all__`**,
setting thư mục lớp cạnh `submission_dir` trong `config/settings.py`,
`SubmissionStore.assign_class/unassign_class`, `POST /submissions` nhận `class_id`,
và **view đọc submission phải lộ `class_id`** (nó là whitelist — thêm vào store mà quên
route thì không ai thấy, không lỗi, không test đỏ).

Bảy route, mỗi động tác một uỹ quyền: `POST /classes` (app token) trả `class_id` +
`write_key` **một lần duy nhất**; `GET /classes/{id}` không token; `PATCH`/`DELETE`/
gán/bỏ gán cần header `X-Class-Key`, **không** phải app token; lưu `sha256(write_key)`
và so bằng `secrets.compare_digest`; `class_id` sai dạng hoặc không tồn tại phải trả
**giống hệt nhau**.

Bắt buộc có đủ 10 test a–j ở mục AC của WP2. Ba cái hay bị bỏ nhất, đừng bỏ:
**(c)** `write_key` chỉ xuất hiện đúng một lần; **(d)** `PATCH` gửi kèm `class_id` phải
422 chứ không bị bỏ qua im lặng; **(e)** sau `DELETE` mọi submission vẫn đọc được bằng
id riêng và `class_id` rỗng. Thêm test âm cho mọi hành vi — xanh vì danh sách rỗng là
xanh bằng thông tin bằng không.

Luật kỹ thuật: `pytest` chỉ có trong `server/.venv`; file `.py` là **CRLF** nên sửa
nhiều dòng bằng script Python đọc/ghi `newline=""` (hoặc patch từng dòng một);
**đọc lại file sau khi vá**; script mà in tiếng Việt thì phải
`sys.stdout.reconfigure(encoding="utf-8", errors="replace")` trước mọi `print`;
script tạm thì **xoá xong viết lại toàn bộ một lần**, đừng sửa bằng `old_text` (công
cụ sẽ tạo file mới chỉ với đoạn vừa thay). Script dừng **trước khi ghi file** nếu một
site không khớp đúng một lần.

Dừng và hỏi tôi, đừng tự quyết: cần tiền/quota; cần xoá file không rõ nguồn gốc; phát
hiện mâu thuẫn giữa ADR 0017 và code hiện có; hoặc sửa của bạn làm đỏ test không liên
quan mà bạn chưa hiểu nguyên nhân. Sửa phát sinh ngoài phạm vi WP2 thì **ghi lại để
báo, đừng làm luôn**.

Báo cáo theo §5 của plan: đã làm / số đo kèm lệnh đã chạy / chặn / câu hỏi cần tôi
quyết — và **ánh xạ từng test a–j sang tên test cụ thể**, đừng bảo "đã viết test".
````


---

## Chế độ F — chạy tiếp WP3 (quyết định của giáo viên)

Dùng sau khi WP2 đã xong và CI đã xanh. Cùng cấu trúc Chế độ E, đã điền sẵn phần
WP3 — trong đó có **một chỗ bạn phải biết là plan vừa được sửa**: uỹ quyền quyết định
**không phải app token**.

````markdown
Tiếp tục plan 12 — **WP3** (sau WP2). Trạng thái đã đo:

- Đã xong: WP0 (dọn + commit), WP1 (ADR 0016), WP2 (lớp full CRUD, ADR 0017, 25 test),
  và commit `c406ea3` dọn nợ format khiến CI đỏ âm thầm.
- Số đo chốt: app 946/946 · server **262 passed + 1 skipped** · guardrails 8/8, 679 file
  · `ruff check` + `ruff format --check` **sạch** (ruff **có** trong `server\.venv`,
  0.14.14; CI chạy đúng hai lệnh đó — chạy chúng trước khi báo xong).
- `git status` sạch, commit mới nhất `c406ea3`.

Bây giờ làm **WP3 — server: quyết định của giáo viên**. Nguồn chuẩn là
`docs/plans/12-run-everything-remaining-2026-09-27.md` §2 WP3 (đã viết lại) và
`docs/adr/0016-class-roster-and-teacher-decisions.md` câu 2. Đọc cả hai trước khi viết
dòng code đầu tiên.

**Điểm quan trọng nhất, đừng làm sai:** route quyết định dùng **`X-Class-Key` của lớp
chứa submission**, **KHÔNG** phải app token. App token là shared secret mà bản app của
nhóm sinh viên cũng giữ; dùng nó ở đây thì nhóm tự duyệt bài của chính mình — đúng lỗ
hổng ADR 0017 đã đóng cho `DELETE`. Dùng lại `verify_key` đã có ở store lớp, đừng viết
lại phép so.

Cần làm: `SubmissionStore.decide()`, route `POST /submissions/{id}/decision`,
`decidedAt` + `note` + cập nhật `status`, **append** vào `history` bằng đúng cơ chế
Tầng 1, `updatedAt = decidedAt` với **một lần đọc đồng hồ mỗi write**, và lộ các field
mới ra view đọc (nó là **whitelist** — thêm vào store mà quên route thì app thấy nút
"Duyệt" còn server không có gì).

Hai trường hợp phải trả **409** kèm lý do, không phải 404 chung: submission chưa thuộc
lớp nào → `not_in_class` (không có lớp thì không có uỹ quyền giáo viên); submission
trỏ tới lớp đã bị xoá → `class_missing`. Id sai dạng và id không tồn tại vẫn trả
**giống hệt nhau**.

Đủ 9 test a–i của WP3. Bốn cái hay bị bỏ, đừng bỏ: **(a)** assert **hình dạng từng mẩu
tin** trong `history` chứ không đếm số mẩu; **(c)** `app_token` đơn thuần **không** quyết
được và trả cùng hình dạng lỗi như người lạ; **(f)** `updatedAt == decidedAt ==
history[-1]["at"]`; **(g)** quyết định lần hai thì `status` là quyết định mới nhất còn
`history` **giữ cả hai**.

Chỉ dùng hai từ vựng `approved | changes_requested` đã chốt ở ADR 0016 — **không tự
phát minh trạng thái thứ ba**, nếu thấy cần thì dừng hỏi tôi.

Luật kỹ thuật: sửa file `.py` (CRLF) bằng script đọc/ghi `newline=""` hoặc patch từng
dòng một, **đọc lại file sau khi vá**; script in tiếng Việt thì cần
`sys.stdout.reconfigure(encoding="utf-8", errors="replace")`; script tạm thì **xoá xong
viết lại toàn bộ**, đừng sửa bằng `old_text` (công cụ sẽ tạo file mới chỉ với đoạn vừa
thay); dừng **trước khi ghi file** nếu một site không khớp đúng một lần.

Dừng hỏi tôi: cần tiền/quota; cần xoá file không rõ nguồn gốc; phát hiện mâu thuẫn giữa
ADR và code; hoặc sửa của bạn làm đỏ test không liên quan mà chưa hiểu nguyên nhân.

Báo cáo theo §5: đã làm / số đo kèm lệnh đã chạy (kể cả hai lệnh ruff) / chặn / câu
hỏi — và **ánh xạ từng test a–i ra tên test cụ thể**, đừng bảo "đã viết test".
````


---

## Chế độ G — vá lỗi đường lỗi, ghi quyết 409, rồi WP4

Ba việc theo thứ tự. **Làm xong bước 1 và báo cáo ngắn, rồi mới sang bước 3** — bước 1
là sửa lỗi trong code vừa viết, không phải mở rộng tính năng, và nó là điều kiện để
WP4 đứng trên nền đúng.

````markdown
Tiếp tục plan 12. Trạng thái đã đo: WP0–WP3 xong, app 946/946 · server **278 passed +
1 skipped** · guardrails 8/8, 680 file · `ruff check` + `ruff format --check` sạch (ruff
**có** trong `server\.venv`, 0.14.14; CI chạy đúng hai lệnh đó, chạy trước khi báo xong)
· `git status` sạch, commit mới nhất `de2bb10`.

# Bước 1 — vá `except Exception` trong `SubmissionStore.decide()`

`server/app/infrastructure/submissions.py` (khoảng dòng 378) đang bọc
`class_store.verify_key(...)` trong `except Exception` rồi luôn ném
`SubmissionClassMissingError`. Hậu quả: **mọi lỗi thật cũng ra 409 `class_missing`** —
lỗi đĩa `OSError`, `AttributeError` do code sai, hay bug trong `compare_digest` — nên
giáo viên thấy "lớp không còn tồn tại" (hành động sai) và nguyên nhân thật biến mất
khỏi log. Đây đúng là loại "chịu lỗi phải chủ ý, không phải im lặng" mà AC (j) WP2 đã
cảnh báo: chịu lỗi thì chủ ý, nhưng **phạm vi** thì rộng hơn ý muốn.

Cách sửa (chọn cách này, đừng chọn cách khác): đổi `ClassStore.verify_key` sang **trả
`bool`** — `True` nghĩa là key đúng, `False` gồm cả "lớp không tồn tại" và "sai key",
vẫn một kết quả duy nhất như trước. Rồi `decide()` **không còn `try` nào**:
`if not class_store.verify_key(class_id, class_key or ""): raise
SubmissionClassMissingError(...)`. Lợi ích thật là **xoá hẳn đường lỗi dễ nuốt** thay
vì thu hẹp nó, và nó giữ đúng ý ADR 0017 option E (một store không chạm vào store
khác). Ba chỗ gọi phải sửa theo: `api/classes.py` (2 chỗ) và `infrastructure/submissions.py`
(1 chỗ) — kiểm lại bằng grep, đừng tin danh sách này.

Bắt buộc có **test âm**: khi store lớp ném một lỗi KHÔNG thuộc họ `ClassError` (ví dụ
`OSError`), route phải trả **500**, không phải 409. Test này bảo vệ luật "lỗi thật không
được mặc áo lỗi nghiệp vụ"; thiếu nó thì `except Exception` sẽ quay lại ở lần sửa sau.
Giữ nguyên hành vi đã test: key sai và lớp mất vẫn trả **cùng một** 409 `class_missing`
(đường ghi không được làm máy dò tồn tại), và 9 test cũ của WP3 vẫn xanh.

# Bước 2 — ghi quyết hiển thị 409 vào plan 12

Trong mục WP5 của `docs/plans/12-run-everything-remaining-2026-09-27.md`, thêm một dòng
ghi chốt: **hai lý do 409 hiện thành hai message khác nhau** — `not_in_class` ("Bài này
chưa được gán vào lớp nào" → vào lớp, gán bài) và `class_missing` ("Lớp không còn tồn
tại, hoặc khoá nhập không đúng" → tạo lại lớp / nhập lại khoá). Cả hai **một dòng, không
modal**. Message thứ hai **phải giữ nguyên sự mơ hồ** "thiếu lớp *hoặc* sai khoá" —
tách thành hai lý do riêng là biến đường ghi thành máy dò tồn tại, đúng thứ ADR 0017 đã
đóng.

# Bước 3 — WP4: activity + watermark

Nguồn chuẩn: plan 12 §2 WP4 và `docs/adr/0016-class-roster-and-teacher-decisions.md`
câu 4. Ba điều chỉnh được nói thẳng trước, vì chúng là chỗ dễ làm sai:

1. **Đừng thêm bảng `read_state` phía server.** ADR 0016 câu 4 đã chốt: "đã đọc" là
   watermark phía app. Nếu bạn thấy cần nó, đó là ADR chưa xong — dừng hỏi tôi.
   Vì thế luật "lần mở app đầu tiên không báo 12 thông báo cũ" **không test được ở
   server**; nó thuộc WP5. Ở đây chỉ cần chứng minh feed **đầy đủ và đúng thứ tự**.
2. **`_now()` chỉ chính xác tới giây**, nên nhiều sự kiện sẽ **trùng `at`**. Feed phải
   có **tie-break xác định** (ví dụ `at` giảm dần, rồi `revision` giảm dần, rồi
   `submission_id`) — nếu không, thứ tự là tuỳ ý và test sẽ lúc xanh lúc đỏ tuỳ
   tốc độ máy. Test của bạn cũng phải tự dựng mốc thời gian **khác nhau từng giây**,
   đừng dựa vào việc hai lần ghi liên tiếp rơi vào hai giây khác nhau (đã có người mắc
   đúng lỗi này ở WP2).
3. `GET /classes/{class_id}/activity` — **không cần uỹ quyền** (id là credential, đúng
   như `GET /classes/{id}`), và `class_id` sai dạng / không tồn tại phải trả **giống hệt
   nhau** như mọi route lớp khác.

Đủ 3 test a–c của WP4: nộp mới → **đúng một** mục mới; nộp vòng 2 → mục mới **khác**
mục cũ chứ không phải cùng một mục bị ghi đè; thứ tự giảm dần với dữ liệu tự dựng có thứ
tự ngược. Cộng thêm: quyết định của giáo viên (event `decided` từ WP3) xuất hiện trong
feed, và lớp rỗng trả **danh sách rỗng** chứ không phải lỗi.

Luật kỹ thuật: sửa file `.py` (CRLF) bằng script đọc/ghi `newline=""` hoặc patch từng
dòng một, **đọc lại file sau khi vá**; script in tiếng Việt cần
`sys.stdout.reconfigure(encoding="utf-8", errors="replace")`; script tạm thì **xoá xong
viết lại toàn bộ**, đừng sửa bằng `old_text`; dừng **trước khi ghi file** nếu một site
không khớp đúng một lần.

Dừng hỏi tôi: cần tiền/quota; cần xoá file không rõ nguồn gốc; thấy mâu thuẫn giữa ADR
và code; hoặc sửa làm đỏ test không liên quan mà chưa hiểu nguyên nhân.

Báo cáo theo §5: **tách riêng bước 1 và bước 3**, số đo kèm lệnh đã chạy (kể cả hai
lệnh ruff), và **ánh xạ từng test ra tên test cụ thể** — đừng bảo "đã viết test".
````

---

## Chế độ H — WP5: ba màn hình giáo viên (rủi ro cao nhất của plan)

Phần lớn prompt này là **những thứ đã dò ra và tốn công**, nên đừng dò lại. Chúng
đo trên cây sau WP4.

````markdown
Tiếp tục plan 12 — **WP5** (app giáo viên). Số đo chốt: app 946/946 · server **335 passed
+ 1 skipped** · guardrails **8/8, 684 file** · `ruff check` + `ruff format --check` sạch ·
`git status` sạch, commit mới nhất `f0d48e9`. (Server đã lên 335 sau WP7; app vẫn 946 vì
WP7 không đụng `app/` — nếu bạn thấy app đỏ thì đó là do chính bạn, không phải nợ cũ.)

Nguồn chuẩn: plan 12 §2 WP5, ADR-0015 (`AppRole` tách khỏi `AppPlatform`),
ADR-0016 (lớp là capability, quyết định append), ADR-0017 (full CRUD, `write_key`).

# Chín thứ đã dò sẵn — đừng dò lại

1. **`file`/`unfile`/`decide` trả ROW MỎNG, không phải submission.** Filing trả
   `{id, class_id, updatedAt}`; quyết định trả `{id, status, decidedAt, updatedAt,
   class_id}` — **không** có group/project/revision/history. Parse thẳng vào model
   submission là nhận row rỗng **không báo lỗi**, và chỉ lộ ra thành cái tên trống
   trên màn hình. Luật: mutation chỉ trả `void`, view-model **đọc lại lớp** sau mọi lần
   ghi, và lần đọc đó là sự thật.
2. **`ApiException` không mang `detail`** (chỉ có `message` + `statusCode`), nên app
   không phân biệt được `not_in_class` với `class_missing` — mà WP5 cần phân biệt vì
   hai lý do dẫn tới hai hành động khác nhau. Sửa: thêm `detail` vào `ApiException`
   và cho `_translate` chép `response.data["detail"]` vào đó, rồi client map detail →
   lý do. Phải có test: hai 409 cho ra **hai** lý do khác nhau, và lý do
   `class_missing` **giữ nguyên sự mơ hồ** "thiếu lớp hoặc sai khoá" (tách nó ra là
   biến đường ghi thành máy dò tồn tại, đúng thứ ADR-0017 đã đóng).
3. **`_write` trong `ApiService` KHÔNG có nhánh PATCH** (chỉ POST/PUT/DELETE), mà
   đổi tên lớp là `PATCH /classes/{id}`. Thêm nhánh PATCH, **và** một tham số tuỳ
   chọn `writeKey` gắn header `X-Class-Key` — đừng tạo client HTTP thứ hai.
4. **Hình dạng JSON server trả về**: `POST /classes` → `{id, name, createdAt,
   updatedAt, write_key, url}`; `GET /classes/{id}` → `{id, name, createdAt,
   updatedAt, submissions[]}` với mỗi phần tử `{id, group, project, revision, status,
   createdAt, updatedAt, has_report, score}`; `PATCH` → không có `submissions`;
   `DELETE` → `{deleted, unfiled, dangling[]}`; `GET /classes/{id}/activity` →
   `{id, events[]}`, mỗi event `{submission_id, group, event, revision, at}`.
5. **`WButton` nằm trong `features/workspace/view/workspace_widgets.dart`** — dùng nó ở
   view của feature khác là phụ thuộc chéo giữa feature. Màn hình giáo viên hãy dùng
   Material button (`FilledButton`/`TextButton`) + `AppSpacing`/`AppRadius`/`ColorScheme`.
6. **`core/providers.dart` và `core/router/` là composition root duy nhất** được
   guardrail miễn trừ (`exclude=` trong luật `core-no-component-machinery`). Chỉ hai
   chỗ đó được import máy móc của component; wire `teacherApiProvider` /
   `teacherStoreProvider` ở đó. View chỉ import view-model, view-model không được
   import dio.
7. **`buildRouter()` hiện không nhận tham số** và mọi test đang gọi nó. Đổi thành
   `buildRouter({AppRoleScope scope = const AppRoleScope.student()})` — **có giá trị
   mặc định**, tham số bắt buộc sẽ phá mọi call site. `AppPlatform` **không được đổi
   một chữ** (test của ADR-0015 giữ lời hứa).
8. **Store giữ `class_id` + `write_key` + watermark nên đụng luật plugin native.**
   `shared_preferences` chỉ được import ở file đã đăng ký trong `NATIVE_PLUGIN_RULES`
   **kèm seam**. Làm đúng đường này: `TeacherStore` là interface, có
   `MemoryTeacherStore` cho test, và hàm seam
   `TeacherStore openTeacherStore(SharedPreferences prefs)` — rồi **đăng ký file đó**
   trong `tools/check_guardrails.py` với seam regex khớp đúng hàm đó. Đừng thêm ngoại lệ.
9. **Khuôn test điện thoại**:
   `tester.view.physicalSize = const Size(390, 844);
   tester.view.devicePixelRatio = 1; addTearDown(tester.view.reset);`
   và **đo kích thước**: `tester.getSize(<nút>).width` so bề rộng nhãn. Đã có nút còn
   **28,2 px** ở bề rộng 390, nhỏ hơn padding 30 px của nút, nhãn bị `ellipsis` mất
   sạch — và **không** dựng `RenderFlex overflowed` nào, nên audit đếm overflow không
   thấy. Hàng nút dùng **`Wrap`**, không `Row` + `Expanded`. Đo trên dữ liệu **đã
   chấm** (`loadDemo()` + `runReview()`), vì đo trên container chưa chấm thì chip toàn
   số `0`, hẹp, không tràn: xanh mà không chứng minh gì.

# Còn bốn điều phải hiện đúng trên màn hình, không được giấu

- Báo cáo giáo viên xem phải mang cờ **"điểm chưa được kiểm định"** (chưa có gold set).
- Hộp thư là **hộp thư kéo khi mở app**, không phải push; watermark "đã đọc" là của
  **máy này**. Chữ trên UI phải nói đúng điều đó.
- `unfiled` khác 0 → **một dòng cảnh báo nhẹ, không modal**; bình thường thì im lặng.
- Hai lý do 409 → **hai message khác nhau**, một dòng, không modal (xem mục 2).

# Điều kiện dừng

Dừng hỏi tôi: cần tiền/quota; cần xoá file không rõ nguồn gốc; phát hiện mâu thuẫn giữa
ADR và code; hoặc sửa làm đỏ test không liên quan mà chưa hiểu nguyên nhân. Ngoài phạm vi
WP5 thì **ghi lại để báo, đừng làm luôn**.

# Báo cáo

Theo §5 của plan, và thêm: **đo width thật của từng nút ở 390×844** (in ra số đo trong
báo cáo, không chỉ "không overflow"), **ánh xạ từng AC sang tên test cụ thể**, và
`flutter analyze --fatal-infos --fatal-warnings` + `dart format` phải sạch (CI kiểm
cả hai).
````


---

## Chế độ I — WP7: bộ dụng cụ gold set (không cần tiền, không cần người)

Sau WP5 thì ba WP còn lại đều bị chặn bởi thứ nằm ngoài tầm tay: WP6 cần file OTES
(~28,7 MB, không nằm trong git) **và** người duyệt quota; WP8 cần khoá API thật **và**
người duyệt chi phí. **WP7 là phần duy nhất tự làm được** — và nó nằm ở
`docs/evidence/scripts/`, **không giao với app**, nên chạy song song với WP5 được.

````markdown
Tiếp tục plan 12 — **WP7, phần làm được: bộ dụng cụ gold set**. Số đo chốt: app 946/946
· server 287 passed + 1 skipped · guardrails 8/8, 681 file · `ruff check` +
`ruff format --check` sạch · `git status` sạch.

# Sự thật phải nói trước khi làm

**Gold set là nơi người khác tự chấm. Người tự dán rồi tự chấm thì đó là gold set vô
giá trị** (plan 10 §3 nói nguyên văn). Nên **không tạo nhãn vàng** — không, không cả
"ví dụ minh hoạ", vì một ví dụ do bạn tự dán sẽ trôi vào sheet thật và làm hỏng đúng
thứ nó sinh ra. Việc bạn làm và làm được trọn vẹn là **bộ dụng cụ**, để khi có hai
người ngồi ký thì việc đo chạy được ngay.

# Cần tạo

1. **`docs/evidence/scripts/goldset_instrument.py`** — theo đúng khuôn các probe cùng
   thư mục: docstring tiếng Việt, có dòng `Chạy:` ghi lệnh chạy thật từ `server/`, và
   có `main()` để chạy tay.
   - `sample_units(rounds, n, seed)` — lấy mẫu **phân tầng**, vì OTES có bẫy đã đo:
     ID trùng có hệ thống (UC04 dùng cho 7+ chức năng, UC021 cho cả "đóng nhóm" lẫn
     "đuổi học viên"), NFR viết thành văn nên parser ra `section`, và thân UC bị tách
     thành `SEC-...` khi mất flow. Tầng: (a) use case có main flow, (b) business rule,
     (c) NFR viết thành văn, (d) use case trùng ID, (e) section unit thực ra là thân
     UC. **In số đếm theo từng tầng** — mọi phát biểu về số lượng đều phải nói rõ đếm
     theo cách nào, vì "63 bảng / 52 ID xuất hiện / 24 ID duy nhất" là ba con số khác
     nhau cho cùng một tài liệu.
   - `annotate_sheet(...)` — ghi CSV với các cột `unit_id, unit_kind, text, annotator,
     finding, criterion_id, note`. Cột **`annotator` là bắt buộc**: thiếu nó thì không
     tính được độ khớp giữa hai người, và không có gì báo lỗi. Sheet phải **trống**,
     dành cho người điền.
   - `agreement(sheet_a, sheet_b)` — tỉ lệ dòng mà hai người khớp trên
     `(finding, criterion_id)`. **Dưới 80% thì phải nói "chưa đủ tin cậy" và TỪ CHỐI**
     in precision/recall (ngưỡng 80% chốt ở plan 10 §3).
   - `precision_recall(sheet_human, sheet_system)` — chỉ chạy được khi agreement đã đạt.
2. **`server/tests/test_goldset_instrument.py`** — vì CI chạy `pytest`, đặt test ở đây
   thì luật mới được thi hành tự động; import script bằng
   `importlib.util.spec_from_file_location`.
   - Lấy mẫu **tất định** với seed cố định, và mỗi tầng khác rỗng trên fixture tự dựng.
   - **Test âm — quan trọng nhất trong cả WP:** hai sheet cố tình lệch nhau ⇒ agreement
     dưới 80% ⇒ công cụ **báo "chưa đủ tin cậy" và không in** precision/recall. Một
     bộ dụng cụ chỉ biết nói "đạt" là bộ dụng cụ vô dụng.
   - Test dương: hai sheet giống nhau ⇒ 100% và có in số.
   - precision/recall trên một case nhỏ **tự tính tay**, chứ không so với con số của
     chính code vừa viết.
3. **`docs/evidence/goldset-instrument-2026-09-27.md`** — nói thẳng: bộ dụng cụ đã sẵn
   sàng; **còn thiếu hai người ký**; **chưa có** số precision/recall nào; kèm hướng dẫn
   cụ thể cho hai người (mở file nào, điền cột nào, đặt file ở đâu, ngưỡng 80% ở đâu).

# Bẫy, đã trả tiền

- **Script này in tiếng Việt, và console này là cp1258** ⇒ `print("Số mẫu…")` sẽ ném
  `UnicodeEncodeError` **giữa lúc chạy**: phần in trước mất, phần ghi file sau chưa
  chạy, và traceback bị nuốt thì trông y hệt "script không làm gì". Phải có
  `sys.stdout.reconfigure(encoding="utf-8", errors="replace")` **trước mọi print**.
- **Tài liệu tiếng Việt**: khớp tiêu đề bằng `re.M` trên phần tiêu đề, **đừng** so
  chuỗi tiếng Anh chính xác (`## Understanding`, `Files / Modules Affected`) —
  `verify_plan_claims.py` đã hỏng vì lý do này **hai lần**.
- **File OTES không nằm trong git.** Sampler phải nhận đường dẫn làm tham số, và test
  dùng fixture nhỏ tự dựng — **không** đọc file 28,7 MB thật, và **không** chạm cache
  thật của server (conftest đã trỏ `SRS_CACHE_DIR` vào thư mục tạm; đừng vòng qua nó).
- Đừng commit thứ gì **trông như nhãn vàng**.

# Báo cáo

Theo §5 của plan, thêm: **đo khớp thực tế** của hai sheet lệch nhau mà bạn tự dựng
(bằng bao nhiêu, và vì sao con số đó đúng), và xác nhận rõ **chưa có** số
precision/recall nào trong repo.
````


---

## Chế độ J — nối bộ dụng cụ với nguồn mẫu đã có trong repo (không đụng app)

WP7 đã xong nhưng **chưa dùng được**: nó cần một file JSON có mảng `units`, và trong
repo chưa ai tạo ra file đó. Nguồn thì **đã có sẵn** — tôi đã dò ra và đo được, nên
bạn không phải tìm lại.

````markdown
Tiếp tục plan 12 — **bước nối nguồn mẫu cho bộ dụng cụ gold set (WP7, phần 2)**. Số đo
chốt: app 946/946 · server 323 passed + 1 skipped · guardrails 8/8, 684 file ·
`ruff check` + `ruff format --check` sạch · `git status` sạch, commit mới nhất `6d8166c`.

# Đã đo sẵn — đừng dò lại

`reviews/workspace-snapshot-2026-09-22-parser1.4.1.json` (1,73 MB, **đã được commit**).
Cấu trúc đo được:

- Cấp cao nhất là **3 key của shared_preferences**: `flutter.srs.proxy.userId`,
  `flutter.srs.workspace.snapshot`, `flutter.srs.workspace.sessions`.
- `flutter.srs.workspace.snapshot` là **chuỗi** (`str`) chứa JSON — tức dữ liệu bị
  **mã hoá hai lớp**. Parse một lần là chưa đủ.
- Bên trong: `fileName, pageCount, sizeLabel, isDemo, units, syllabusFindings,
  referenceFindings, blueprintFindings, findingStatus, diagramPageCount, result,
  documentFingerprint`.
- `units` có **240 phần tử**; mỗi phần tử có `key, id, title, text, kind, section,
  pageIndex, malformed, selected, status` (unit đầu có `text` dài 861 ký tự ⇒ **có text
  thật để người ký đọc**).
- Phân bố `kind`: `Section` 168, `Use case` 61, `Functional` 5, `Non-functional` 4,
  `Unknown` 2.

# Việc cần làm

1. **Thêm loader vào `docs/evidence/scripts/goldset_instrument.py`** — ví dụ
   `load_units_from_snapshot(path)`, dùng được bằng cờ `--source snapshot <path>`.
   - **Đừng hardcode tên key.** File có 3 key; hãy chọn key nào parse ra object có
     `units` là list — đó là cách chịu được file đổi shape lần sau thay vì chết.
   - Phải xử lý lớp mã hoá thứ hai (chuỗi JSON bên trong JSON).
   - Trả về `units` ở đúng hình dạng mà `sample_units()` đã nhận, và **giữ nguyên logic
     phân tầng** đã có (mọi tầng hiện đang dùng: `section_is_uc_body`, `duplicate_uc_id`,
     `uc_with_main_flow`, `business_rule`, `nfr_as_prose`, `other`).
   - Vẫn **thuần stdlib**, vẫn **không** import `app.*` hay `server.*` — test
     `TestIsolation` quét AST và phải **vẫn xanh**.
2. **Test mới** trong `server/tests/test_goldset_instrument.py`:
   - Loader đúng trên **fixture nhỏ tự dựng** có đúng cái hình dạng hai lớp kia
     (bốc từ `tmp_path`) — đây là test chính, không phụ thuộc file lớn.
   - Một test đọc **file thật** trong `reviews/`, khẳng định ra **240 unit** và rằng
     unit đầu có `text` khác rỗng. Cho phép bỏ qua (`skipif`) nếu file vắng mặt, để
     CI không đỏ vì một file bằng chứng bị dọn đi.
   - Test end-to-end: từ file thật → lấy mẫu → sinh sheet **trống** (`finding` và
     `annotator` rỗng). Không được sinh ra nhãn nào.
3. **Ghi nguồn và cảnh báo phạm vi vào `docs/evidence/goldset-instrument-2026-09-27.md`:**
   - Nguồn: đường dẫn file, 240 unit, phân bố `kind` đo được, và **parser 1.4.1**.
   - **Cảnh báo phải nằm trong file, không nằm trong đầu ai đó:** 168 unit `Section` ở
     đây là **hệ quả của parser 1.4.1** — thân UC bị tách thành `SEC-…`, đúng cái bẫy mà
     1.4.2 đã sửa. Vì thế gold set lấy từ nguồn này phạm vi là **tiêu chí trên từng
     unit** (`finding` / `criterion_id`), và **không** dùng để kết luận gì về phân đoạn
     unit. Nếu sau này cần chấm cả phân đoạn thì phải dump lại bằng 1.4.2, và lúc đó
     mới cần một nút export trong app — ghi luôn điều đó.
   - Nhắc lại: **chưa có** số precision/recall nào, và còn thiếu hai người ký.
4. Cập nhật dòng trạng thái của WP7 trong `docs/plans/12-run-everything-remaining-2026-09-27.md`:
   nguồn mẫu **đã có**, bộ dụng cụ **chạy được**; thứ còn thiếu chỉ là hai người ký.

# Bẫy đã trả tiền

- Script in tiếng Việt ⇒ `sys.stdout.reconfigure(encoding="utf-8", errors="replace")`
  **trước mọi print**, không thì chết giữa lúc chạy và trông như "không làm gì".
- **Đừng tạo nhãn vàng**, kể cả ví dụ minh hoạ. Sheet sinh ra phải **trống**.
- Không đụng cache thật của server, không cần API key, không tốn quota.
- Sửa file bằng script đọc/ghi `newline=""`; **đọc lại file sau khi vá**; script tạm thì
  xoá xong **viết lại toàn bộ một lần**.

# Dừng hỏi tôi

Nếu loader buộc phải đọc `reviews/` bằng cách nào đó không thuần stdlib, hoặc nếu bạn thấy
cần nối thẳng vào app để lấy payload — dừng hỏi, đừng tự mở rộng phạm vi. Đừng sửa
gì trong `app/`: nút export chỉ cần khi nào ai đó quyết định chấm cả phân đoạn unit.

# Báo cáo

Theo §5 của plan, thêm: **số unit thật đọc được từ file thật**, và dán lại đoạn cảnh báo
phạm vi 1.4.1 mà bạn đã ghi vào file evidence (để tôi kiểm chữ, không kiểm ý).
````


