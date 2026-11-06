# ADR-0020 — Firestore schema contract: một danh mục collection, một hình dạng doc, một bên ghi

**Status:** Proposed
**Date:** 2026-11-06
**Deciders:** Amy
**Supersedes (một phần):** [ADR-0019](0019-firebase-identity-and-data-ownership.md) — file ADR-0019 được giữ nguyên, xem mục 2.1
**Related:** ADR-0016, ADR-0017, [Plan 13](../plans/13-firebase-fastapi-cloudinary-integration.md) §2.2 và §2.4, [model Firebase của mobile](../../mobile/docs/firebase-data-model.md), [`mobile/firestore.rules`](../../mobile/firestore.rules), [`contracts/firestore/collections.json`](../../contracts/firestore/collections.json), [`contracts/firestore/*.schema.json`](../../contracts/firestore/), [`tools/tests/test_firestore_contract.py`](../../tools/tests/test_firestore_contract.py)

## 1. Bối cảnh

Firestore hiện không có schema được thi hành. Hai client dùng Firestore (mobile và admin-web) dùng chung một project `srs-ai-prm`, server FastAPI cũng ghi vào đó, nhưng tên collection lại rải rạc ở ba nơi khác nhau:

| Collection | Writer thật | Reader thật |
|---|---|---|
| `users/{uid}` | mobile (`AuthService._syncUserProfile`) | mobile, admin-web |
| `users/{uid}/projects/{projectId}` | mobile (`FirestoreProjectsService`) | mobile, admin-web |
| `crash_logs/{logId}` | mobile (`FirebaseCrashlyticsService._mirrorLog`) | admin-web |
| `srs_reports/{reportId}` | server FastAPI (`ReportIndex`, Admin SDK) | admin-web |
| `admins/{adminUid}` | tạo tay từ Console (rules cấm client ghi) | rules (`isAdmin()`) |

Hệ quả đã thấy trong source:

- Tên collection không có nơi khai báo trung tâm; thêm collection mới là thêm chuỗi trong code.
- Rules và code có thể lệch nhau mà không ai biết (ví dụ `users.createdAt`, `users.fcmTokens`, `crash_logs.appVersion`: rules cho phép nhưng không writer nào ghi).
- Hai client khác nhau đọc cùng collection nhưng không có hình dạng doc được khoá, nên đổi field là đổi ngầm.
- Plan 13 §2.2 và §2.4 đã chốt mô hình đích, nhưng mô hình đó chưa được ghi thành hợp đồng kiểm được.

Bước này (WP2 phần A) **chỉ** ghi tài liệu, contract và test. Không sửa code trong `mobile/`, `admin_web/`, `desktop/`, `server/`.

## 2. Quyết định

### 2.1. Phạm vi supersede của ADR-0019

ADR-0019 giữ nguyên file và trạng thái Accepted. ADR-0020 supersede **đúng ba phần** của nó:

| Phần của ADR-0019 | Sau ADR-0020 |
|---|---|
| §Decision 1 (danh tính là `request.auth.uid`), §Decision 2 (`write_key` → `ownerUid`), §Decision 4 (vocabulary `approved|needsRevision|notAccepted`), §Decision 5 (thời gian là server time) | **Giữ nguyên.** Không đổi. |
| §Consequences: "mobile data và store `.classes/.submissions` của server là hai nơi riêng; không có gì migrate giữa chúng" | **Tạm giữ**, vẫn đúng cho phần dữ liệu học vụ. Nhưng phần *file/SRS* đã không còn tách: mobile gọi FastAPI để upload và server là bên ghi duy nhất của `srs_reports`. Phạm vi supersede chỉ mở khi người dùng trả lời mục OPEN 1. |
| ADR-0019 không có hợp đồng schema | **Bổ sung** bằng ADR-0020: danh mục collection, hình dạng doc, bên ghi. |

ADR-0019 có ghi: nếu mở rộng phạm vi vai trò thì rules `ownerUid`-only phải nới và "this ADR superseded by 0020". **Phần đó chưa xảy ra**: rules hiện tại vẫn là `ownerUid`-only cho dữ liệu client, và mô hình phân vai trò mới (mục 2.2) được ghi ở đây nhưng **chưa mở rules**. Mở rules là việc của WP3/WP5, không phải của ADR này.

### 2.2. Bộ vai trò chuẩn và nơi cấp quyền

- Vai trò chuẩn: `supervisor | student | admin` (Plan 13 §2.2).
- **Nguồn quyền**: `accessGrants/{uid}`, có `role`, `active`, `revision`, `updatedAt`, `updatedBy`. Client không tạo/sửa grant.
- `admins/{uid}` hiện tại là **bước tạm**: rules dùng `exists()`, không có writer/reader nào trong code đọc field của nó. Plan 13 §2.2 thay bằng `accessGrants/{uid}`.
- `users/{uid}.role` **không** phải input cấp quyền (giữ ADR-0019). Giá trị `teacher` là alias của `supervisor` và **chỉ** được đổi trong migration có ghi nhận.
- Thiếu grant không tự trở thành Supervisor.
- Đường đăng nhập desktop Windows và web (Plan 13 §2.3) không thuộc ADR này.

### 2.3. Quy ước field chung

Áp dụng cho dữ liệu chuẩn mới (Plan 13 §2.4), **không** áp dụng hồi tố cho doc đang chạy:

| Quy ước | Nội dung |
|---|---|
| `schemaVersion` | = 2 cho dữ liệu chuẩn mới (collection đang chạy dùng 1 hoặc không có) |
| `revision` | theo entity; command cập nhật mang `expectedRevision` |
| `createdAt` / `updatedAt` | `serverTimestamp()`, rules yêu cầu `== request.time` (giữ ADR-0019 §5) |
| `createdBy` / `updatedBy` | uid hoặc thông tin bootstrap |
| Timestamp | UTC; ngày thuần `yyyy-MM-dd` theo Asia/Saigon |
| ID | ID mới do server sinh, độc lập mã/tên |
| Enum lạ | trả `invalidData`, không tự đổi thành giá trị an toàn |
| Update | chỉ ghi field được command cho phép |
| Dữ liệu lớn | để ở subcollection/asset, không nhét cả app vào một doc |

### 2.4. Bên ghi (write ownership) và collection CHỈ server ghi

Mỗi collection có **một** bên ghi. Không double-write.

| Bên ghi | Nghĩa là gì |
|---|---|
| Client (mobile, admin-web) | Đi qua Firebase Web SDK nên **chịu Firestore Rules**. |
| Server FastAPI | Đi qua Firebase Admin SDK nên **bỎ QUA Rules** → API phải tự kiểm UID và quyền nghiệp vụ, không được tin client. |

Collection **CHỈ server FastAPI ghi** (theo Plan 13 §2.4 và code hiện tại):

- `assets` (đường dẫn hiện tại: `srs_reports`) — metadata tệp sau khi Cloudinary xác nhận bytes.
- `reports` — báo cáo.
- Upload intent nội bộ — đường dẫn hiện chưa chốt tên.
- Migration manifest/mapping nội bộ — client không được ghi.

Client **không** được ghi bất kỳ collection nào trong bốn nhóm trên; Admin Web chỉ đọc `srs_reports`, `crash_logs`, `users`.

### 2.5. Quyết định `srs_reports` → `assets` — ĐÃ THỰC HIỆN (WP2 phần B, 06/11/2026)

Plan 13 §2.4 đặt file metadata ở `assets`; `srs_reports` là tên cũ của đợt Lab 3. Ta chốt:

- Tên đích: `assets`.
- **Đã đổi đồng bộ trong một lượt**: writer (`server/app/infrastructure/report_index.py`), rules (`mobile/firestore.rules`), reader Admin Web (`admin_web/.../srs_reports_repository.dart`) và danh mục (`contracts/firestore/collections.json`) dùng `assets`.
- **Không cần migrate dữ liệu**: chưa từng có document nào được ghi vào `srs_reports`. Mọi lần ghi Firestore thật đều lỗi `DefaultCredentialsError` (server chưa có service account), nên collection cũ rỗng; bản ghi chỉ tồn tại trong `InMemoryReportIndex` của test.
- **Không đổi gì ngoài tên collection**: tên feature/folder `srs_reports` trong admin_web và giá trị `cloudinary_folder` của server giữ nguyên, vì đó không phải tên collection Firestore (đổi `cloudinary_folder` là đổi đường dẫn file trên Cloudinary).
- Shape không đổi, nên một schema dùng chung: [`assets.schema.json`](../../contracts/firestore/assets.schema.json).
- Tên collection nay nằm trong hằng số `FirestoreCollections` (mobile và admin_web) và trong `COLLECTION` của server; guardrail mới (luật 10 trong `tools/check_guardrails.py`) cấm viết literal `.collection('...')` ngoài các file đó.

### 2.6. Hình thức hợp đồng

| Thứ | Quy tắc |
|---|---|
| Danh mục | [`contracts/firestore/collections.json`](../../contracts/firestore/collections.json): mỗi collection có `path`, `status` (`implemented`|`planned`), `writers`, `readers`, `schemaVersion`, `schema`, `notes`. |
| Schema | Mỗi collection `implemented` có một file `contracts/firestore/<tên>.schema.json`: JSON Schema 2020-12, `additionalProperties: false`, có `x-contract-version`. |
| Fixture | `contracts/fixtures/firestore/<tên>.json`: một document hợp lệ theo schema. Timestamp biểu diễn bằng chuỗi ISO-8601 UTC. |
| Kiểm | [`tools/tests/test_firestore_contract.py`](../../tools/tests/test_firestore_contract.py) kiểm 4 nhóm: implemented ↔ rules match, literal collection trong code ↔ danh mục, file schema hợp lệ và đóng, fixture khớp schema. |
| Đổi hợp đồng | Bump `x-contract-version`, sửa fixture, và ghi lý do. Schema là hợp đồng, không phải tài liệu. |

## 3. Hệ quả

- Collection mới phải khai trong danh mục trước khi code gọi tới; test (b) chặn trường hợp quên.
- Collection có trong rules mà không có trong danh mục (hoặc ngược lại) bị test (a) bắt.
- Schema là nơi khai field, nên các field "rules cho phép nhưng không writer nào ghi" (`users.createdAt`, `users.fcmTokens`, `crash_logs.appVersion`) được ghi rõ trong mô tả thay vì để người đọc tưởng là đã có dữ liệu.
- Danh mục ghi cả phần **chưa có code**, nên Plan 13 §2.4 không còn là tài liệu đọc-lệch-nhau với code.

### 3.1. Khoảng cách giữa chuẩn và hiện trạng (chưa xử lý ở bước này)

| Chuẩn (§2.3) | Hiện trạng trong code |
|---|---|
| `schemaVersion = 2` | `users/{uid}/projects` dùng `schemaVersion = 1`; `users/{uid}`, `crash_logs`, `srs_reports` không có field này |
| `revision`, `createdBy`, `updatedBy` | Chưa collection nào có |
| `createdAt`/`updatedAt` mọi doc | `users/{uid}` không ghi `createdAt`; `crash_logs` chỉ có `timestamp`; `srs_reports` chỉ có `uploadedAt` |
| Field reader đọc nhưng không writer nào ghi | Admin Web đọc `srs_reports.status` (fallback `'pending'`) nhưng server không ghi field đó; reader cũng đọc `users.createdAt` (fallback `lastSignInAt`) nhưng writer không ghi |
| `assets` là tên đích | Đã đổi đồng bộ ở WP2 phần B (§2.5); không có dữ liệu cũ để migrate |
| Quyền theo `accessGrants` | Rules vẫn dùng `admins/{uid}` và `ownerUid` (§2.2) |

## 4. OPEN — cần người dùng quyết

1. **Mobile Lab 3 có được phụ thuộc server FastAPI không?** ADR-0019 nói "custom backend servers are out of scope", nhưng [`mobile/lib/services/srs_service.dart`](../../mobile/lib/services/srs_service.dart) hiện đã gọi server (xin upload intent rồi finalize), còn base URL của server lấy từ `MOBILE_API_BASE_URL` (dart-define), và server là bên ghi duy nhất của `srs_reports`. Nếu câu trả lời là "không", mobile không thể đẩy file lên Cloudinary qua server → cần đường upload khác, và mâu thuẫn này phải giải quyết ở cấp quyết định, không phải ở tầng code.
2. **`admins/{uid}` có field gì?** Không writer/reader nào trong code chạm field của doc này; rules chỉ kiểm `exists()`. Schema hiện để trống field, nên một doc admin đang tồn tại ở Console có thể không khớp schema. Chốt: bỏ schema, hay khai field và có writer.
3. **`reports` ai ghi?** `mobile/docs/firebase-data-model.md` §2 nói owner tự tạo; Plan 13 §2.4 nói "writer/reader/Rules cùng path"; rules hiện cho phép owner create/update/delete. Ba nguồn chưa thống nhất.
4. **Khi nào bump `schemaVersion` từ 1 lên 2?** Cần một mốc cụ thể (WP5 hay trước bàn giao Lab 3).
5. **Doc dự trữ `courseCodes`/`classCodes`/`groupNames`** có trong model mobile nhưng không có trong bảng §2.4 của Plan 13 — giữ hay bỏ?
6. **Tên `uploadIntents` và `migrationManifests`** chưa chốt (Plan 13 chỉ ghi "nội bộ").
7. **`users.createdAt`, `users.fcmTokens`, `crash_logs.appVersion`**: rules cho phép nhưng chưa writer nào ghi — giữ trong allowlist (chờ FCM/WP11) hay bỏ?

## 5. Trạng thái bước này

Đã tạo: ADR này, `contracts/firestore/collections.json` (32 mục: 5 `implemented`, 27 `planned`), 5 file schema, 5 fixture, và `tools/tests/test_firestore_contract.py`.

Đã làm thêm ở WP2 phần B (06/11/2026): đổi đồng bộ `srs_reports` → `assets` và đưa tên collection vào hằng số `FirestoreCollections` của mobile và admin_web (§2.5).

Chưa làm (cần chốt trước khi mở rộng): thêm `accessGrants`, mở rules theo vai trò, và kiểm field của doc ghi thật với schema trên emulator (test hiện kiểm **tên** collection, shape file và fixture — chưa kiểm payload thật của writer với schema, trừ writer server đã có test trong `server/tests/test_assets.py`).
