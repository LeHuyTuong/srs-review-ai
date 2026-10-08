# ADR-0020 — Real accounts: the capability posture is replaced by a user table, sessions, and a role on every route

**Status:** Accepted — **đảo ADR-0016**, đè brief (`/kickoff-company` ghi "KHÔNG làm tài khoản/đăng nhập thật")
**Date:** 2026-10-08
**Deciders:** Tường (quyết định chủ sở hữu, xác nhận 4 lần trong phiên 2026-10-08)
**Related:** ADR-0016 (a class is a capability — **bị đảo bởi ADR này**), ADR-0017 (class CRUD, write key), ADR-0019 (web-ui is a mock), ADR-0015 (`AppRole`), `server/app/api/submissions.py`, `server/app/infrastructure/submissions.py`, `web-ui/src/app/auth.ts`, `app/lib/core/providers.dart`, `docs/plans/11-teacher-app-2026-09-27.md`

## Context

ADR-0016 chọn **B** — lớp học là một `class_id` capability, và ghi thẳng ở
§Options rằng A ("User table + login") bị loại vì nó tạo *reader identity* mà
server chưa có consumer nào. Plan 11 dòng 44 nói cùng một điều bằng tiếng Việt:
"Giáo viên tạo lớp → app giữ `class_id`. **Đó chính là đăng nhập của giáo viên**".
Cả hai ghi rõ giới hạn: ai cầm link thì xem được cả lớp và **không thu hồi được**.

Brief của `/kickoff-company` đóng băng quyết định đó: "KHÔNG làm admin, KHÔNG làm
tài khoản/đăng nhập thật", kèm luật dừng: "Nếu một quyết định cần danh tính người
dùng thật → DỪNG và hỏi, đừng tự thêm hệ thống auth."

**Chủ sở hữu đã chọn đảo.** Bốn lần liên tiếp trong phiên 2026-10-08:

1. "phải có login chứ"
2. mức độ: "Tối thiểu chạy được: user + password hash + session"
3. phạm vi: "Login cả server + web-ui + app Flutter (bỏ mô hình mã)"
4. xác nhận cuối khi được nói rõ goal text vẫn cấm: "Đè brief: làm login thật cả server + web-ui + app"

Đây là quyết định hai lần chạm đúng cái mà ADR-0016 gọi là *expensive to undo*
(§Consequences: phần đắt-để-hoàn-tác là thứ tạo reader identity), nên nó là một
**ADR đảo**, không phải một bản vá. ADR-0016 §Consequences đã chỉ định trước con
đường này: "the next status is an ADR amendment".

## Options considered

| # | Option | Pros | Cons | Answers which question |
|---|---|---|---|---|
| A | **Giữ capability như ADR-0016, không làm login** | đúng brief; đã xong Bước 1–2; không có gì phải hoàn tác | không đáp ứng yêu cầu chủ sở hữu; không có danh tính để "danh sách của tôi" hay thu hồi quyền | scope |
| B | **User table + password hash + session, bỏ mô hình mã** | danh tính thật; thu hồi được; mọi route biết *ai*; danh sách trở nên có nghĩa | đảo ADR-0016; Bước 2 vừa commit phải viết lại; "đọc không cần credential" phải bịt; thêm schema + migration + test cho auth | scope |
| C | Login chỉ server + web-ui, app Flutter giữ capability | Bước 2 giữ nguyên | hai phía dùng hai mô hình xác thực — nợ kỹ thuật ngay từ đầu, và "ai là ai" khác nhau tuỳ client | scope |
| D | Login nhưng giữ `class_id` làm đường vào thứ hai | không phá gì | hai đường vào = hai bề mặt tấn công, và đường yếu nhất định nghĩa an ninh của cả hệ | scope |

**B được chọn.** A bị chủ sở hữu bác tường minh; C và D đều để lại hai mô hình
sống song song, đúng thứ ADR-0016 §Context gọi là "identity" bị rò rỉ.

## Decision

1. **Server có bảng `users`** với `username` duy nhất, `password_hash`, `role`
   (`teacher | student`), `created_at`. Mật khẩu băm bằng **`hashlib.scrypt`**
   (stdlib — repo này đã tránh thêm dependency native cho persistence, xem
   ADR-0011) kèm **salt riêng từng người**, và so bằng `secrets.compare_digest`.
   Không có "quên mật khẩu", không email xác thực, không OAuth — chủ sở hữu chọn
   mức tối thiểu chạy được, và giới hạn đó là *có chủ đích*, ghi ở §Consequences.
2. **Session là một token opaque** (`secrets.token_urlsafe(32)`), lưu **băm** ở
   server, đặt trong cookie **`HttpOnly; SameSite=Lax; Path=/`**. Không có JWT:
   một token có thể thu hồi bằng cách xoá hàng, còn JWT thì không, và yêu cầu ở
   đây là *thu hồi được*.
3. **Mọi route biết người gọi.** `deps.current_user` đọc cookie, tra bảng, trả
   `User`. Route ghi của giáo viên (`/submissions/{id}/decision`, comment của
   giáo viên, `PATCH` comment) đòi `role == teacher` **và** quan hệ với lớp;
   route của sinh viên đòi `role == student`. `class_id`/`write_key` **không còn
   là** chứng thư — chúng thành *khoá ngoại*, không phải mật khẩu.
4. **`GET /submissions` trở thành có thật**: trả bài nộp **mà người gọi được
   thấy** — giáo viên thấy lớp mình dạy, sinh viên thấy nhóm mình thuộc. Đây là
   thứ ADR-0016 §Options nói không thể có khi chưa có danh tính; giờ có.
   Để làm được, bảng `users` mang thêm **`class_id`** (giáo viên) và **`group`**
   (sinh viên) — hai cột nullable, và một tài khoản chỉ nên có cột ứng với vai
   của nó. Migration là **thêm cột**, không đổi kiểu cột cũ, nên hàng đã có vẫn
   đọc được và một user chưa gắn lớp/nhóm thấy danh sách **rỗng** chứ không lỗi.
   Đây là chỗ đánh đổi thật: danh sách có nghĩa kéo theo việc tài khoản phải biết
   mình thuộc đâu, và câu hỏi "ai gắn lớp cho giáo viên" là việc quản trị mà
   ADR-0020 §Consequences đã nói là **chưa** làm (không admin, không màn gán).
5. **web-ui bỏ mock session.** `web-ui/src/app/auth.ts` gọi `/auth/login`,
   `/auth/logout`, `/auth/me`. Màn hình giữ nguyên; nguồn sự thật của "ai đang
   đăng nhập" đổi từ `localStorage` sang server.
6. **App Flutter có màn đăng nhập** và gửi cookie/token như web-ui. Bước 2 vừa
   commit (`2c52142`, `4685d4b`) **giữ lại phần thread** nhưng phần "id trong path
   là chứng thư" phải sửa.
7. **ADRs cũ không bị xoá.** ADR-0016 và 0017 ở nguyên trong lịch sử; chỉ mục
   `docs/adr/README.md` ghi ADR-0020 đảo 0016, kèm ngày — không có gì bị viết đè
   im lặng.

## Consequences

- **Mất: tính chất "đọc không cần credential".** Hôm nay `GET /submissions/{id}` là
  capability — cầm id là đọc được. Sau ADR này, mọi đọc đi qua session, nên một
  link báo cáo chia sẻ phải kèm đường dẫn có xác thực hoặc một token đọc riêng.
  Đây là **đánh đổi thật**: đổi "không thu hồi được" lấy "phải có tài khoản".
- **Mất: Bước 2 đã commit không còn đúng nguyên trạng.** `student_repository.dart`
  và `teacher_repository.dart` phải mang credential; `student_store.dart` giữ
  danh sách link thành bookmark thay vì chứng thư. Code và test của chúng là đầu
  vào, không phải kết quả.
- **Được: thu hồi được.** Xoá một hàng session là hết quyền trên thiết bị đó —
  thứ `class_id` không làm được (ADR-0016 §Consequences: "no revocation once a
  link leaks").
- **Được: danh sách trở nên có nghĩa.** "Bài của tôi" lọc theo danh tính thay vì
  "ai gửi tôi id này".
- **Nợ, chấp nhận:** không quên mật khẩu, không xác thực email, không đổi mật
  khẩu. Một deployment công khai sẽ cần cả ba; ở đây chúng là *quyết định hoãn*,
  không phải *thiếu sót bị bỏ quên*.
- **Rủi ro, nói to:** băm scrypt mặc định của stdlib có tham số yếu hơn
  argon2id/bcrypt. Chấp nhận vì không thêm dependency native, và vì đây là công
  cụ tự chạy; một sản phẩm thật đổi sang argon2id (ADR-0011 đã đi đúng con đường
  "stdlib trước, dependency sau khi có lý do").
- **Không quyết ở đây:** rate limit đăng nhập, lockout, và CSRF. `SameSite=Lax`
  chặn phần lớn CSRF xuyên site; một endpoint đổi trạng thái cần CSRF token là
  việc của vòng sau, ghi lại chứ không giả vờ đã xong.

## Verification

- `test_auth.py` — mật khẩu đúng/mật khẩu sai trả cùng một 401 (không tiết lộ
  username tồn tại hay không); token session không đọc được raw trong store;
  logout làm token chết ngay.
- `test_sessions.py` — cookie đặt `HttpOnly` và `SameSite`; một session hết hạn
  thì route ghi trả 401 chứ không 500.
- Hồi quy Bước 2: bộ test hiện có (1019 Flutter, 387 server) phải được **sửa
  theo**, và mỗi test cũ đỏ vì thiếu session phải đỏ với thông điệp nói ra điều
  đó, không phải bằng một `KeyError`.
- Kiểm chứng ngược: xoá một hàng session thì request kế tiếp **phải** 401 — chạy
  thật, không suy luận. Nếu nó vẫn 200 thì việc thu hồi chưa xong.
