# ADR-0021 — Author comes from the session, not the request body

**Status:** Accepted — hoàn tất ADR-0020 §Decision 3 ("Mọi route biết người gọi"), không đảo gì
**Date:** 2026-10-08
**Deciders:** Tường (chọn "Siết route ghi theo phiên + giảng viên dùng phiên" khi được hỏi ở Bước 3)
**Related:** ADR-0020 (bảng `users`, session, `deps.current_user`), ADR-0019 (luồng trao đổi hai phía), ADR-0016 (đã bị ADR-0020 đảo), ADR-0017 (`write_key`), `server/app/api/submissions.py`, `server/app/infrastructure/submissions.py`

## Context

ADR-0020 §Decision 3 hứa: "Mọi route **biết người gọi**… Route ghi của giáo
viên đòi `role == teacher` **và** quan hệ với lớp". Commit `837098a` và
`7e01aac` dựng bảng `users`, session, và `deps.current_user`, nhưng **bốn route
ghi của luồng trao đổi chưa dùng nó**:

| Route | Xác thực hiện tại | `author` hiện tại |
|---|---|---|
| `POST /submissions/{id}/decision` | `X-Class-Key` header | không có (ngầm định teacher) |
| `POST /submissions/{id}/comments` | submission-id (student) hoặc `X-Class-Key` (teacher) | **client khai trong body** |
| `POST /submissions/{id}/comments/{cid}/replies` | như trên | **client khai trong body** |
| `PATCH /submissions/{id}/comments/{cid}` | `X-Class-Key` header | không có |

Điều này **chưa phải một lỗ hổng**, và phải nói chính xác vì sao: khai
`author: "teacher"` vẫn phải qua `class_store.verify_key`, nên một sinh viên
không có class key vẫn bị `409 class_missing`. Phòng thủ hiện tại **đúng**.

Nhưng nó đúng **một cách tình cờ**, và điều tình cờ đó là thứ đáng sửa:

1. **Danh tính suy từ chứng thư, không từ tài khoản.** Cùng một class key được
   chia cho cả nhóm giảng viên (ADR-0017), nên "ai đã viết nhận xét này" chỉ
   trả lời được *một lớp*, không trả lời được *một người*. ADR-0020 §Consequences
   đã ghi mất mát này: reader identity.
2. **`author` do client khai là một trường quyết định quyền.** `add_comment`
   rẽ nhánh theo nó (`if author == "teacher": <đòi class key>`). Một trường mà
   quyền phụ thuộc vào nó **không nên** đến từ phía gọi. Nó chỉ đang an toàn vì
   nhánh teacher còn một cổng thứ hai phía sau.
3. **Nó để lại một đường sai chưa bị đóng:** nếu vòng sau có ai nới cổng thứ hai
   (ví dụ thêm "giảng viên đã đăng nhập thì khỏi cần key" mà quên siết `author`),
   hole mở ra **không có test nào đỏ**, vì test hiện tại kiểm *thiếu key* chứ
   không kiểm *khai sai vai*.

## Options considered

| # | Option | Pros | Cons | Answers which question |
|---|---|---|---|---|
| A | **Giữ nguyên; chỉ thêm comment giải thích** | 0 rủi ro; bốn route đang xanh | `author` vẫn là input quyết định quyền; ADR-0020 §3 vẫn nợ; đường sai ở (3) ở nguyên | phạm vi |
| B | **Ép `author` theo vai trò phiên KHI có phiên; giữ đường class-key khi không có** | đóng đúng điểm yếu; deep link giảng viên còn sống; không phá client nào chưa cập nhật; test cũ vẫn có nghĩa | hai đường vào cùng tồn tại — nhưng **khác** D của ADR-0020: đường thứ hai không mở quyền mới, nó chỉ là *cùng* quyền với một credential khác | phạm vi + tương thích |
| C | **Bỏ hẳn class-key; mọi route ghi chỉ theo phiên** | một đường vào duy nhất, dễ lý luận nhất | phá deep link giảng viên (QR/link dán) — thứ plan 11 vẫn dùng; phải sửa Flutter + web-ui + test cùng lúc, rủi ro cao nhất | phạm vi |
| D | **Ép `author` theo phiên, VÀ từ chối `author` trái vai một cách tường minh (422)** | như B, cộng một test đỏ được khi ai đó nới cổng thứ hai | thêm một nhánh lỗi | phòng thủ |

**Chọn B + D.** Lý do B: quyết định sở hữu ở bước này là "siết route ghi theo
phiên" **và** giữ luồng giảng viên đang chạy. Lý do D: một ràng buộc không có
test thì không tồn tại, và ở đây test phải kiểm **khai sai vai** chứ không chỉ
thiếu chứng thư — đó là khác biệt giữa bắt được regression và không.

Không chọn C vì nó là **Bước 4 của một kế hoạch khác** (gỡ capability), không
phải "siết theo phiên"; trộn chúng vào một lượt là tự tạo rủi ro mà không ai
yêu cầu.

## Decision

1. **`author` là DẪN XUẤT khi có phiên.** `deps.current_user` chạy ở cả bốn
   route. Nếu có phiên, `author` **bị ghi đè** theo `role` của phiên
   (`teacher`/`student`), bất kể body khai gì. Client gửi `author` sai vai nhận
   **422 `author_role_mismatch`** — không im lặng sửa, vì sửa im lặng thì client
   hỏng vẫn "chạy" và người viết ra lỗi không bao giờ biết.
2. **Không có phiên thì giữ đường cũ.** `X-Class-Key` (hoặc submission-id cho
   sinh viên) vẫn xác thực như ADR-0019, và `author` trong body vẫn quyết định
   nhánh — với ràng buộc ở (1) áp dụng: **một request không có phiên mà khai
   `author: "teacher"` phải kèm class key** (luật cũ, giữ nguyên và giữ test cũ).
3. **Class key trở thành credential THỨ HAI cho cùng một quyền, không phải quyền
   thứ hai.** Nói rõ để người sau không đọc B thành D của ADR-0020: đường
   class-key không cho ai thêm quyền gì nó chưa có; nó chỉ là cách vào khi client
   chưa có phiên (Flutter deep link, web-ui link dán).
4. **`/auth/me` phải trả đủ để client chọn quyền.** Nó đã trả `role`,
   `classId`, `group` từ `7e01aac`; ADR này **không** đổi shape đó, chỉ nói rõ
   nó là hợp đồng mà bốn route này dựa vào.
5. **`decide_submission` và `resolve_comment` không nhận `author`.** Chúng không
   có trường đó trong body và vẫn không có; phiên chỉ dùng để **phân quyền**,
   không để ghi danh tính — chưa có cột nào lưu "ai quyết định". Đây là một
   **khoảng trống có chủ đích**, ghi ở §Consequences, không phải thiếu sót.

## Consequences

- **Được: `author` ra khỏi tầm với của client khi có phiên.** Trường mà quyền
  phụ thuộc vào nó giờ do server đặt; một sinh viên đã đăng nhập **không thể**
  khai `teacher` dù có class key hay không — và có test khẳng định đúng điều đó.
- **Được: ADR-0020 §Decision 3 hết nợ.** Bốn route ghi của luồng trao đổi giờ
  thật sự "biết người gọi".
- **Mất: một request hợp lệ có thể nhận 422 mới.** Một giảng viên gửi
  `author: "student"` (đổi vai trong UI) sẽ bị từ chối thay vì được chấp nhận
  như trước. Đây là **đổi hành vi quan sát được**, nên nó phải có test và phải
  nói ra trong báo cáo; không được coi là "chỉ là refactor".
- **Giữ: hai đường vào.** Nói thẳng rủi ro: bề mặt tấn công rộng hơn một đường.
  Chấp nhận vì đường thứ hai không cấp quyền mới, và vì gỡ nó là một quyết định
  khác chưa được đưa ra.
- **Không quyết ở đây: lưu "ai đã làm".** `decide` và `resolve` không ghi lại
  danh tính người quyết định — không có cột, không có audit log. Với một công cụ
  chạy nội bộ và một lớp có 2–3 giảng viên thì class key là mức phân giải đủ;
  nhưng một deployment nhiều lớp sẽ cần `decided_by`/`resolved_by`, và đó là
  **migration + UI + test**, không phải một dòng `payload["by"] = user["id"]`.
  Ghi lại chứ không giả vờ đã xong (cùng lối với ADR-0020 §Consequences).
- **Không quyết ở đây: rate limit và CSRF cho bốn route này.** `SameSite=Lax`
  vẫn là toàn bộ phòng thủ CSRF như ADR-0020 đã ghi. ADR này làm CSRF **quan
  trọng hơn** một bậc, vì giờ một request cross-site có phiên sẽ được server
  gán `author` thay vì bị chặn bởi việc thiếu `author` hợp lệ — nói ra, không
  giấu.

## Verification

- `server/tests/test_author_from_session.py` (mới) — sáu khẳng định, mỗi cái
  phải **đỏ được** nếu bỏ bản vá:
  1. sinh viên có phiên khai `author: "teacher"` → **422**, và **không** comment
     nào được ghi (kiểm bằng số comment trước/sau, không chỉ mã trạng thái);
  2. giảng viên có phiên khai `author: "student"` → **422** cùng lý do;
  3. giảng viên có phiên, **không** gửi class key → **201** (phiên đủ tư cách);
  4. giảng viên có phiên trên lớp **khác** với `class_id` trong tài khoản →
     **403/409**, không phải 201 — phiên không được cấp quyền xuyên lớp;
  5. không có phiên + `author: "teacher"` + **không** class key → **409**
     (luật ADR-0019 giữ nguyên, không bị nới bởi ADR này);
  6. không có phiên + `author: "student"` + submission-id hợp lệ → **201**
     (đường cũ không bị chặn nhầm).
- Toàn bộ suite server phải còn xanh: `server/.venv/bin/python -m pytest tests/`.
- Kiểm chứng ngược bằng tay: xoá đúng dòng gán `author = user["role"]` trong
  `add_comment` rồi chạy lại file test — khẳng định (1) **phải** đỏ. Nếu nó vẫn
  xanh thì test đang đo một thứ khác với thứ nó nói đang đo, và bản vá chưa
  thật sự được bảo vệ.

## Amendment 2026-10-08 — what was actually built

Ghi lại sau khi làm, vì ADR viết trước thì phần "đã làm" phải khớp phần "đã hứa":

- **Đã làm đúng (1)–(5).** `current_user_optional` (không ném 401 khi thiếu
  phiên) là mảnh còn thiếu để B khả thi — `deps.current_user` cũ *bắt buộc* có
  phiên, dùng nó ở bốn route này sẽ chặn luôn deep link.
- **Khác một chi tiết so với §Verification (4):** ca "giảng viên có phiên trên
  lớp khác" trả **404**, không phải 403/409. Lý do: hàng `class_id` của tài khoản
  không khớp thì với route đó bài nộp **không tồn tại trong tầm nhìn của người
  gọi**, và trả 403 sẽ xác nhận id đó có thật — đúng luật "một hình dạng 404"
  mà `read_submission` đã giữ. Test khẳng định **404**, và ghi rõ vì sao.
- **Ca (2) đổi thành 403, không 422:** khai `author` trái vai khi đã có phiên là
  *thiếu quyền viết dưới vai đó*, không phải *body sai định dạng* — 422 nói
  "sửa body đi", mà sửa body thì cũng không được phép. Test khẳng định 403.
