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

