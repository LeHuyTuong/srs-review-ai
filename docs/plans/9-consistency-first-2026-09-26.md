# Plan 9 — Bỏ đi hướng "platform" trước, làm chắc hạt nhân consistency (2026-09-26)

> **TRẠNG THÁI 2026-09-26 (cuối phiên): P0a · P0b · P1 · P2 · P3-seam · chain 3 XONG.**
>
> | Phase | Kết quả | Bằng chứng |
> |---|---|---|
> | **P0a** vision thật | **ĐẠT** — 7/8 trang `unreadable=0`, 3 lỗi chính tả bắt kèm `[sic]` | `docs/evidence/vision-reality-2026-09-26.md` + `.json` |
> | **P0b** chain 2 | Xong — `result.relations` giữ lại thay vì vứt; `fk_matrix_mismatch` vào **6** chỗ | `cross_artifact_checker.dart` + 11 test |
> | **P1** chain 1 đa ngữ | Xong — regex `[A-ZÀ-Ỹ]`, `_stem` gọi chung `stemOf` | `docs/evidence/chain1-vietnamese-2026-09-26.md` |
> | **Chain 3** Sequence↔Class | Xong — 5 luật đếm `scoring.md:119` mỗi luật 1 test | `cross_artifact_chain3_test.dart` (11 test) |
> | **P2** submission | Xong — 5 route, capability-id, không cần auth | `test_submissions.py` (16 test) |
> | **P3 seam** | Xong — `core/role/app_role.dart`, `AppPlatform` **không đụng** | `docs/adr/0015`, `app_role_test.dart` |
>
> **Test:** app **938 xanh / 0 đỏ** (841 → 938), server **228 pass + 1 skip** (161 → 228),
> `dart analyze lib test` sạch, `check_guardrails.py` 8/8 xanh (674 file).
>
> **Còn MỞ:** AC4 chỉ chứng minh *cơ chế*, **chưa đo lại chain 1 trên OTES thật**.
> P3 màn hình giáo viên và P4 (Group/Schedule/Notification) chưa làm — xem §11.
> **Chain 3 chưa vào thang điểm**: không có gold set (roadmap M2 vẫn MỞ).

**Nguồn:** người dùng đề xuất mở rộng thành *platform quản lý đồ án* (web nhóm +
mobile giáo viên + review đa artifact), rồi thu hẹp lại: không làm web, một Flutter
duy nhất, mobile = giáo viên, desktop = nhóm. Plan này trả lời bằng số đo trên
working tree, không bằng đồng cảm.

**Kết luận một dòng:** ý tưởng đúng hướng, **thứ tự đề xuất đánh đổi sai**. Tầng
platform (~70–80% khối lượng) không chứng minh được gì về AI, còn hạt nhân
cross-artifact — thứ *làm nên tên đồ án* — thì đang đứt đúng mắt xích nối và có
một rủi ro chưa ai kiểm chứng: **vision chưa từng chạy thật trên tài liệu thật**.

---

## 0. Bốn phát hiện, đều có số đo

### 0.1 Mobile app tồn tại, nhưng là **desktop bị thu nhỏ** — không phải mobile app

Không phải cảm tính, mà là hệ quả của hai ADR đã ký:

| Bằng chứng | Chỗ | Nghĩa là gì |
|---|---|---|
| "mọi số trong `AppViewportData` resolve về giá trị **trước khi** workstream desktop tồn tại" | `docs/adr/0006` quyết định 3 | Mobile **không** được thiết kế; nó là web layout thu nhỏ |
| Mọi uplift màn lớn gate trên `isDesktop`, không phải trên `formFactor` | `app_viewport.dart:49-58` | `AppFormFactor.phone` không có bất kỳ quyết định layout nào riêng |
| **Cấm cả họ bottom sheet trong `app/lib`**, thực thi bằng guardrail luật 8 | `docs/adr/0014`, `tools/check_guardrails.py` | Phone mà không có bottom sheet = lệch chuẩn mobile. Người sau muốn làm đúng sẽ **bị CI chặn** |
| 4 destination, tất cả thuộc về *một sinh viên, một tài liệu, một lần chấm* | `app_router.dart:16-20` | Không tồn tại màn hình nào là "danh sách nhóm", "lịch review", "thông báo" |
| `features/workspace` = **14.801 dòng**, 48% `app/lib` | đo bằng `Get-Content | Measure-Object -Line` | Công sức đã đổ hết vào đúng workflow một-người-một-tài-liệu |

**Kết luận:** app **chạy được** trên Android. Nó không phải mobile client. Khác
biệt đó là lý do "có mobile rồi mà chưa hợp lí" — và nó **rẻ** để sửa, vì
responsive hạ tầng đã có (`AppViewport`, `StatefulShellRoute`), thiếu đúng là
*thông tin* chứ không thiếu *kỹ thuật*.

### 0.2 Tầng platform = 0%, và có thật

Grep recursive toàn bộ `server/app/**/*.py` cho `class User|class Group|class
Teacher|class Submission|class Schedule|teacher|role` → **một kết quả duy nhất**, và
nó là `"role": "user"` trong payload Gemini. Không có dữ liệu nghiệp vụ nào.

- `deps.py:97` `require_app_token` — so 1 shared secret. Đó là API key, không phải auth.
- `deps.py:106` `caller_id` — đọc header `X-User-Id` do client tự khai, fallback IP. **Không ai ký**, nên không dùng phân quyền được; chỉ đếm quota.
- `cache.sqlite3` là *cache*, không phải database nghiệp vụ.

Sáu dòng trong sơ đồ backend của đề xuất (`Authentication`, `Group/Project`,
`Submission`, `Review Schedule`, `Notification`, + cache đa artifact) đều là việc
mới hoàn toàn. Đây là phần **ít giá trị nghiên cứu nhất** trong toàn bộ đề xuất.

### 0.3 Cross-artifact — hạt nhân nghiên cứu — đang đứt đúng mắt xích

`review-rules/references/scoring.md:111` khai 7 chain. Thực tế trong app:

| Chain | Trạng thái | Bằng chứng |
|---|---|---|
| 1 · Naming drift | 🟡 thuần text | `crossArtifactName`, `contradiction_pass.dart` |
| 2 · FK matrix (ERD ↔ data dictionary) | ❌ | probe r20, ghi trong scoring.md |
| 3 · Sequence ↔ Class (0.5× lifeline + 0.5× message) | ❌ | "port bước 2" |
| 4–6 · ERD↔UC, activity↔UC | ❌ | chain 2,4,5,6 |

Và chain 1, thứ *đã có*, **yếu hơn vẻ ngoài**: `docs/evidence/r13_otes_deterministic_ceiling.md:29`
ghi **0 finding trên OTES**. Nguyên nhân không phải tài liệu sạch — regex ở
`contradiction_pass.dart:113` là `[A-Z][a-z]+`, chỉ khớp tiếng Anh, còn OTES viết
tiếng Việt. **Đây là false negative do giới hạn code, không phải kết luận về tài liệu.**

Mắt xích đứt: `/diagram` (`server/app/infrastructure/diagram.py`) **đã trả về**
`DiagramDescribe` — danh sách element, relation, unreadable. `ContradictionPass`
chỉ đọc text requirement. **Không có dòng nào nối hai thứ đó.** "SRS nói payment
nhưng không entity nào" — đúng cái ví dụ trong đề xuất — **chưa tồn tại trong code**.

Đáng chú ý: `contradiction_pass.dart:98` đã set sẵn
`requiresVisionEvidence: true` với lý do đúng — finding text-only chỉ là *tín
hiệu*. Kiến trúc đã đặt chỗ, thiếu mắt xích.


### 0.4 Rủi ro chưa ai kiểm chứng, và nó nằm ở đầu P0

`docs/plans/8-ai-sees-images-2026-09-23.md:16` đo trên cache thật:

> namespace `diagram` trong cache: **0 entry**

Nghĩa là `/diagram` **chưa từng chạy trên tài liệu thật một lần nào**. Cả
chain 2 và chain 3 đều cần vision. Đây là giả định lớn nhất của đề xuất, và nó
**chưa có bằng chứng nào ủng hộ**.

Nói thẳng với chính mình: nếu vision không đọc được chữ trên ảnh render từ PDF ở
host này (biết trước rằng A4 ở cap 1600px chỉ ~1.9 dots/pt, và trap #3 "model đọc
sai rồi tự tin" đã được ghi trong prompt), thì chain 2/3 **không làm được**, và
P0 phải thu hồi về mức chain 1 đa ngữ. Vì vậy **P0a đo trước, P0b mới code**.

---

## 1. Thứ tự, và lý do đảo

Không sắp theo độ dễ sửa, mà theo **giá trị chứng minh được đổi lấy rủi ro**:

| Phase | Deliverable | Chạm hạ tầng mới? | Nếu hỏng, mất gì |
|---|---|---|---|
| **P0a** | Chạy `/diagram` thật trên OTES/HisWise, đo tỉ lệ đọc được chữ | Không | 1 buổi sáng |
| **P0b** | Nối `DiagramDescribe` ↔ chain 1 + chain 2 | Không | 1–2 tuần |
| **P1** | Regex chain 1 đa ngữ, đo lại OTES | Không | 1 ngày |
| **P2** | Submission bằng capability-URL, **không cần auth** | Có, nhỏ | 3–5 ngày |
| **P3** | `AppRole` + mobile teacher shell | Có, vừa | 1–2 tuần |
| **P4** | Group / Schedule / Notification | Có, lớn | 3–4 tuần, **giá trị nghiên cứu ≈ 0** |

Điểm cốt lõi: **P2 đưa hệ thống thành multi-user mà không viết auth**, vì
`/uploads/presign` (capability token, HMAC, hết hạn) và `/share` (id 128-bit là
credential, CSP sandbox) **đã có và đã qua test bảo mật**
(`test_uploads.py`, `test_share.py`). Đánh đổi: link = credential, không phân
quyền thật. Với đồ án là hợp lý; với sản phẩm thì không.

Và **P4 là chỗ sẽ mất nhiều thời gian nhất, nói ít nhất.** Đừng để nó chen
vào giữa P0 và P2.

---

## 2. P0a — Đo vision thật (GATE, không code)

**Mục tiêu:** biết `/diagram` có đọc được không trước khi xây 2 chain phụ thuộc nó.

- Chạy `POST /diagram` thật (không mock) cho 3–5 trang hình của **HisWise SDS**
  (tiếng Anh, có sơ đồ vector) và 3–5 trang của **OTES** (tiếng Việt).
- Chỉ dùng crop theo `DocumentMap.figurePages` + `bbox` — `/documents/render` đã
  có sẵn, đúng kỷ luật của sds-reviewer.
- **Ghi lại, mỗi trang**: số element, số relation, và **tỉ lệ chữ đọc được vs
  `unreadable[]`**. Đây là số quyết định, không phải cảm nhận.
- Lưu response thật vào `docs/evidence/vision-reality-2026-09-26.md`.

**Gate (AC1):** nếu tỉ lệ chữ đọc được < 60% trên HisWise → **P0b chỉ làm chain 1
đa ngữ**, chain 2/3 chuyển sang deferred với lý do đo được. Đây là kịch bản có
thật, phải chấp nhận trước khi code chứ không sau.

**Cạm bẫy đã biết, phải né:**
- Đừng kết luận từ 1 trang. Chạy hết danh sách rồi tính tỉ lệ.
- `unreadable[]` **không phải** lỗi — prompt đã cấm đoán. Trang mà ra `unreadable`
  nhiều là trang *hiển thị* chứ không phải trang hỏng.
- Đừng dùng `flutter test` để đo: `pdfx` chết cứng trên test host, và
  `PageImageRenderer` giờ đã có probe nên sẽ **degrade im lặng** thay vì ném.
  Raster bằng `pdftoppm` trên host rồi đo offline.

---

## 3. P0b — Nối `DiagramDescribe` vào chain 1, thêm chain 2

**Mục tiêu:** sinh ra đúng ví dụ trong đề xuất — *"requirement mentions payment
but no corresponding entity was found"*.

**Bước 1 — luật nối (thuần Dart, không LLM):** lấy `DiagramDescribe.elements` của
trang ERD, chuẩn hoá bằng **đúng** hàm `_stem` mà `ContradictionPass` đang dùng
(`contradiction_pass.dart:123`), rồi so với stem trong requirement. Nhất quán
hoá một chỗ — nếu mỗi bên tự chuẩn hoá khác nhau, "khớp/không khớp" là vô nghĩa.

**Bước 2 — chain 2 (FK matrix), theo `scoring.md:112`:** tỉ lệ FK vừa khớp kiểu
vừa khớp data dictionary. Cần `DiagramRelation.label` + `arrowhead_side` mà
`/diagram` **đã trả sẵn**. Công thức đếm phải viết ra file, không để trong đầu —
luật của `scoring.md` §"luật đếm chặt".

**Bước 3 — hạ cờ chân thực, không nâng thành điểm:** finding mới **không** được
tự động tính vào thang điểm khi chưa có gold set. `docs/roadmap.md` M2 đang để
**MỞ** vì chưa có bộ annotation để đo precision/recall. Công bố "AI tự phát hiện
thêm N mâu thuẫn" mà không kèm đo là phát biểu không có bằng chứng — đúng cái
mà ADR-0012 (`0012-issue-criterion-identity.md`) đã làm đúng khi tách
`criterion_id` khỏi `type`.

**Bước 4 — CheckId mới:** thêm id vào **cả ba** nơi, cùng một lần, nếu không sẽ
drift:
1. `CheckId` enum (Dart)
2. `contracts/review.schema.json` `$defs/CheckId` — enum này đã có lần drift trước,
   schema tự ghi "adding a CheckId without adding it here is the drift to watch for"
3. `server/app/contracts/schemas.py` nếu server cần biết

**AC2:** test hồi quy với fixture `DiagramDescribe` giả — entity trùng tên qua
bốn cách viết khác nhau (chữ hoa/thường, số ít/nhiều, có khoảng trắng thừa) phải
gộp về 1; khác hẳn thì không gộp. **AC3:** test đo chạm chuẩn `scoring.md` — tay
tính 2–3 trường hợp, viết kỳ vọng vào test.

---

## 4. P1 — Chain 1 đa ngữ (nhanh nhất, làm ngay được)

`0 finding trên OTES` là giả định sai, và nó sửa được trong một ngày.

- `_extractEntityName` (`contradiction_pass.dart:112`) hiện chỉ khớp tiếng Anh,
  **đã tự thừa nhận** ở docstring dòng 26–29 ("cross-language matching: the strip
  is ASCII only").
- Sửa regex + thêm bảng từ khóa tiếng Việt (`Sinh viên`, `Khách hàng`, `Tác nhân`…),
  theo đúng tiền lệ `missingActor` đã làm việc này cho EN+VN
  (`r13_otes_deterministic_ceiling.md:30`).
- **Đo lại OTES** và ghi số vào `docs/evidence/`. Đây là lý do tồn tại của phase
  này: sửa xong mà không đo lại thì không biết có sửa đúng không.

**AC4:** số finding chain 1 trên OTES **tăng so với 0**, kèm bảng so sánh. Nếu
vẫn 0 thì regex không phải nguyên nhân — phải tìm nguyên nhân thật, đừng đoán.


---

## 5. P2 — Submission không cần auth

**Mục tiêu:** nhóm nộp tài liệu → giáo viên mở link thấy báo cáo. Chạy được
end-to-end, không cần user table.

- Dùng lại nguyên văn hai primitive đã có: `/uploads/presign` (token HMAC, hết
  hạn, 14 security test) + `/share` (id 128-bit, CSP sandbox, traversal guard).
- Một submission = 1 capability id. Group điền, giáo viên mở, ai có link thì
  thấy — **đúng mô hình R2 của plan 6**, đã được chấp nhận và đã test.
- **Ghi rõ nợ kỹ thuật:** không có phân quyền, không ai biết ai là giáo viên ai là
  sinh viên, không có lịch sử ai sửa gì. Đây là giới hạn của lựa chọn này, không
  phải sự cố — phải viết vào tài liệu chứ không giấu.

**AC5:** round-trip test (POST → GET trả đúng byte), 401 không token, 413 quá
trần, traversal 404. **AC6:** `app/test` xanh, `server/tests` xanh.

---

## 6. P3 — Mobile giáo viên (chỉ sau khi có dữ liệu thật)

Đây là phase dễ làm hỏng nhất, vì nó **đụng ADR-0014**.

**Bắt buộc — ADR 0015 trước khi viết dòng UI nào.** Cần chốt, không thể suy:
- Bottom sheet trên phone là chuẩn Material, nhưng guardrail luật 8 **cấm** cả họ
  `showModalBottomSheet` trong `app/lib` và test đã khẳng định sự vắng mặt của nó
  (`qa_p1_adversarial_test.dart:547`). Phải chọn: giữ luật nguyên vẹn (mobile đi
  theo chrome full-screen) hoặc **thu hồi một phần** luật 8 cho `formFactor == phone`
  — và nếu thu hồi thì ghi ADR, không sửa guardrail trong im lặng.
- Có bổ sung `AppRole` vào `AppPlatform`, hay giữ `AppPlatform` thuần *thiết bị*
  và đặt `AppRole` ở tầng feature? Tôi nghiêng về **tách**: `AppPlatform` trả lời
  "tôi đang chạy ở đâu", `AppRole` trả lời "tôi là ai" — trộn hai thứ làm role trở
  thành thứ phải kéo theo cả platform.

**Điều P3 KHÔNG được làm:** `AppFormFactor.phone` hiện không có **bất kỳ quyết
định layout nào riêng** (`app_viewport.dart:49-58`). Đừng lấp bằng cách nhân bản
desktop thu nhỏ — đó chính là cái làm app hiện tại "chưa hợp lí".

**AC7:** `test/desktop/app_breakpoint_test.dart` (đang pin 9 bề rội) xanh; thêm
test mới cho phone ở 390×844 và 360×640. **AC8:** đo **kích thước**, không chỉ đếm
exception — theo bài học đã trả giá trong repo: một `Expanded` bị bóp cạn **không**
dựng `RenderFlex overflowed` nào, nhãn bị `ellipsis` mất sạch, audit đếm overflow
thấy 0 lỗi (28.2 px vs 30 px padding ngang của `WButton`).
---

## 7. P4 — Group / Schedule / Notification (nếu còn thời gian)

Là CRUD thuần, không đo được gì về AI. Ba cảnh báo đã kiểm chứng từ working tree:

1. **Quota chắc chắn vỡ.** `settings.py:67` `rate_limit_per_day = 50` **mỗi người**.
   Giáo viên chấm 20 nhóm × 2 vòng là vượt quota ngay ngày đầu tiên. Trần 40
   unit/lượt ở app được đặt để giữ 10 request dự phòng cho *một sinh viên*
   (`b10b215`), giữ được cho cả lớp thì không. Cần mô hình quota theo **lớp**, không
   theo người.
2. **Vercel + state trên đĩa.** Upload store, share store, cache SQLite đều ghi
   local disk; `settings.py:143` tự thừa nhận filesystem serverless chỉ ghi được
   ngoài `/tmp`. Cache chịu được (ADR-0011 đã chấp nhận degrade về memory) —
   nhưng **submission thì mất mỗi cold start**. Sửa bằng config không được; phải
   chọn host khác hoặc object storage. Đây là quyết định trước khi viết code P4.
3. **Body cap 4,5 MB** đã có đường vòng presigned upload — nhưng nếu sau này có
   web, nhớ IndexedDB gắn với origin: mỗi lần `flutter run -d chrome` ra origin
   mới là mất sạch lịch sử (đã dính 2026-09-25, mất 2 lần trước khi hiểu).

---

## 8. Nguyên tắc bất di bất dịch khi động vào các phase này

Lấy nguyên văn từ bẫy đã trả giá, áp dụng cho code mới:

1. **Mọi giá trị đi vào prompt phải đi vào cache key** (`c3fc786`). Chain mới lấy
   `context_text` từ `DiagramDescribe` ⇒ context đó phải vào key.
2. **Mọi call plugin native phải có probe hoặc fake.** Đừng trông `try/catch` quanh
   call — `pdfx.openData` vứt future của `assertHasPdfSupport()` không await, lỗi rơi
   thẳng vào zone của test đang chạy (`bf44431`).
3. **Đo lại sau khi sửa, và dùng `while (takeException() != null)`** — `takeException()`
   chỉ trả MỘT lỗi, phần còn lại nằm trong hàng đợi, test xanh với lỗi còn sót.
4. **Mọi bước đổi luật chấm port từ `review-rules/` vào app đi qua
   `review-rules/adapters/app-port-map.md` trước** — không port thẳng vào code.
5. **Đừng hồi sinh snapshot.** Session thuộc về lượt chấm; draft chỉ giữ
   `projectName`/`projectInfo`/`humanIssues` (`b27d481`).
6. **Thêm provider/đường đọc ở tầng import phải nằm trong `try`** — một tiện ích
   phụ không được biến import tốt thành lỗi.

---

## 9. Acceptance Criteria

| # | Tiêu chí | Cách đo |
|---|---|---|
| **AC1** | Vision thật đã đo | `docs/evidence/vision-reality-2026-09-26.md`: tỉ lệ chữ đọc được trên HisWise + OTES. Dưới 60% → chain 2/3 deferred **có lý do đo được** |
| **AC2** | Chuẩn hoá stem dùng chung | Test 4 biến thể viết hoa/số ít/số nhiều/khoảng trắng gộp về 1; khác hẳn thì không gộp |
| **AC3** | Công thức chain 2 có test | Tính tay 2–3 trường hợp, viết kỳ vọng vào test; tài liệu hoá theo `scoring.md` |
| **AC4** | Chain 1 đa ngữ đo lại | Số finding trên OTES > 0, kèm bảng so sánh trước/sau trong `docs/evidence/` |
| **AC5** | Submission round-trip | POST → GET đúng byte; 401 / 413 / traversal 404 |
| **AC6** | Hồi quy xanh | `cd app && flutter test`; `cd server && .venv\Scripts\python -m pytest tests/` — **qua venv**, `pytest` trần luôn trả `No module named pytest` |
| **AC7** | Không drift CheckId | id mới có mặt ở Dart enum **và** `contracts/review.schema.json`; test contract xanh |
| **AC8** | Không phá layout desktop | `test/desktop/app_breakpoint_test.dart` 9 bề rội xanh |
| **AC9** | Mọi claim có ledger | Không phát biểu "AI phát hiện thêm N vấn đề" mà không kèm số đo; chưa có gold set thì ghi rõ **provisional** |

## 10. Files / Modules bị ảnh hưởng

| Phase | File chính | Ghi chú |
|---|---|---|
| P0a | `docs/evidence/vision-reality-*.md` (mới) | chỉ tài liệu, không code |
| P0b | `app/lib/deterministic_checks/checks/contradiction_pass.dart`; `app/lib/diagram_audit/models/diagram_audit.dart`; `contracts/review.schema.json` | **3 nơi cùng lúc** cho CheckId |
| P1 | `contradiction_pass.dart` | cùng file với P0b — gộp một lần, đừng vá hai lần |
| P2 | `server/app/infrastructure/uploads.py`, `share.py`, `api/uploads.py`; `server/app/contracts/schemas.py` | tái dùng primitive, không viết auth |
| P3 | `app/lib/core/platform/app_platform.dart`; `app/lib/core/router/app_router.dart`; `docs/adr/0015-*.md` (mới) | **ADR trước, UI sau** |
| P4 | `server/app/domain/`, `api/`; `contracts/` | cần ADR 0016 về host + quota, viết sau |

## 11. Risks

- **Lớn nhất: P0a cho kết quả tệ.** Vision có thể không đọc được chữ trên ảnh render
  từ PDF ở host này. Kịch bản đã được ghi sẵn (chỉ làm chain 1) — nên **tệ nhưng
  không chết**, và bạn biết ngay tuần đầu thay vì tháng thứ ba.
- **Chain 3 khó hơn hình dung:** phải đo đúng "lifeline là class" và "message là
  operation khai báo", mà `scoring.md:113` đã viết sẵn luật đếm chặt vì hai
  người chấm từng lệch. Cứ làm chain 2 trước, chain 3 chỉ khi chain 2 có số.
- **Đừng để P3 hút người.** Nó *thấy được* app chạy, còn P0/P1 thì không — dễ bị
  ưu tiên nhầm vì "cảm giác tiến bộ". Tiêu chí ở `docs/roadmap.md` là **gate**,
  không phải cảm giác.
- **Thiếu thời gian:** bỏ P4 trước, rồi bỏ P3, **không bỏ P0b+P1**. Bỏ P4/P3 thì
  vẫn còn một hệ thống có luận điểm nghiên cứu; bỏ P0/P1 thì còn lại CRUD.

## 12. Bắt đầu ngay

1. **P0a** — đo vision thật, viết ledger. Không sửa code.
2. Đọc lại `docs/roadmap.md`: 3 gate MỞ (gold set, precision/recall ảnh, E2E
   desktop sau 2026-09-21) là **việc còn treo thật**, và chúng thuộc đúng phase
   P0/P1 này. Làm P0/P1 không phải là chệch hướng — đó là đóng nốt các gate đang
   mở.
3. Viết **ADR 0015** trước P3, không phải trong lúc làm P3.
