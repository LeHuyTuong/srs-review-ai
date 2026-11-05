# Mô hình dữ liệu Firebase của Supervisor Mobile (phạm vi Lab 3)

Ngày: **04/11/2026**. Trả lời cho `mobile-firebase-contracts.md` (draft 26/10, DEP-01..12 đều OPEN) ở **phạm vi Lab 3**. Quyết định danh tính nằm ở [ADR-0019](../../docs/adr/0019-firebase-identity-and-data-ownership.md). Đây là hợp đồng thiết kế, **chưa phải** schema đã triển khai: mọi mục dưới đây chuyển sang "đã làm" chỉ khi có code, rules và test đi kèm.

## 1. Quy ước chung

| Mục | Quyết định |
|---|---|
| Chủ sở hữu | Mọi doc có `ownerUid` (Auth UID). Rules Lab 3: `resource.data.ownerUid == request.auth.uid` cho đọc/sửa/xóa; `request.resource.data.ownerUid == request.auth.uid` cho tạo. Không có ngoại lệ đọc chéo user |
| Mọi doc có thêm | `schemaVersion:int`, `revision:int` (theo entity, không có revision toàn cục), `createdAt`, `updatedAt` (`serverTimestamp`, rules ép `== request.time`) |
| ID | Ổn định, độc lập mã/tên. Seed giữ ID fixture (`se1701`, `s1`, `review-001`...). ID mới do client sinh theo `prefix-<microsecondsSinceEpoch>-<seq>` như hiện tại |
| Thời gian | `Timestamp` UTC. Ngày thuần (semester, deadline) lưu `yyyy-MM-dd` theo Asia/Saigon. Chuỗi `dd/MM/yyyy · HH:mm` chỉ sinh ở presentation |
| Actor | `authorUid`/`actorUid`. Tên hiển thị là dữ liệu trình bày, **không** dùng để cấp quyền |
| Counter lưu sẵn | **Không lưu** `groupCount/studentCount/projectCount/pendingReviews`. Tính bằng `count()` hoặc từ query. (Fixture đã lệch: SE1701 lưu `pendingReviews=4` tính ra 6; SE1702 lưu `projectCount=2` tính ra 1) |
| `null` vs `[]` | `labOverride`: **vắng field = kế thừa**, `[]` = cố ý rỗng. Codec đọc/ghi phải giữ phân biệt này và có test |
| Số nguyên | `maxGroupMembers`, `capacity`... ép về `int` khi đọc (`memberLimit` hiện rơi về 5 nếu giá trị không phải `int`) |
| Enum lạ | Đọc ra `AcademicFailure(invalidData)`; không mặc định thành giá trị an toàn hay thành `approved` |
| Trường lạ | Update chỉ ghi các field nằm trong allowlist của lệnh; không đọc cả JSON rồi ghi ngược |
| Xóa | Ưu tiên archive. Lịch sử (version, decision, audit) append-only, không cascade |

## 2. Collection

Cột Quyền ghi theo Lab 3 (một Supervisor = một `ownerUid`). `—` = không cho phép.

| Collection | Field cốt lõi | Tạo | Sửa | Xóa | Dùng ở màn |
|---|---|---|---|---|---|
| `users/{uid}` | displayName, photoUrl, email, role (`supervisor`, không dùng để cấp quyền), fcmTokens[] | Chính chủ, allowlist field | Chính chủ | — | Profile, Login |
| `users/{uid}/inbox/{id}` | kind, entityId, reviewId?, title, body, createdAt, readAt? | Chính chủ (trong transaction nghiệp vụ hoặc nhận FCM) | Chính chủ, chỉ `readAt` | Chính chủ | Notifications |
| `semesters/{id}` | name, academicYear, startDate, endDate, archived | Owner | Owner | — (archive) | Semester, Dashboard |
| `courses/{id}` + `courseCodes/{normCode}` | code, name, archived; reservation.courseId | Owner, trong cùng transaction với reservation | Owner (đổi code: release + acquire cùng transaction) | — (archive) | Courses |
| `offerings/{id}` | courseId, semesterId, ruleSetId, teachingMethod, defaultDeadline, labs[] (hoặc `labs` subcollection) | Owner | Owner | — | Offering |
| `ruleSets/{id}` | name, version, status, aiEnabled, aiRequiredBeforeSupervisor, criteria[], passThreshold, improveThreshold, allowedFormats | Owner | Owner, `version` +1, bản cũ không ghi đè | — | Rule library |
| `classes/{id}` + `classCodes/{norm}` | code, offeringId, state (`active|archived`), capacity, maxGroupMembers, schedule, session, ruleSetOverride?, labOverride? | Owner | Owner (không giảm dưới occupancy) | Owner khi không còn phụ thuộc, nếu không thì archive | Classes |
| `students/{id}` + `enrollments/{classId_studentId}` | academicCode (`^[A-Z]{2}\d{6}$`), displayName, email; enrollment: classId, studentId | Owner, cả batch all-or-nothing, kiểm capacity | Owner | Owner | Directory, Class |
| `groups/{id}` + `groupNames/{classId_normName}` | classId, name, memberIds[] / membership docs, projectId? | Owner | Owner (đúng lớp, đúng giới hạn, 1 sinh viên/nhóm) | Owner khi rỗng và không có project có lịch sử | Groups |
| `projects/{id}` | classId, groupId?, name, state, startDate, deadline, hasHistory | Owner | Owner | Owner nếu `hasHistory == false` | Projects |
| `projectRegistrations/{id}` | classId, groupId, submitterUid, status (`pending|approved|changesRequested|rejected`), reason?, projectId? | Owner (seed / nhận) | Owner: chuyển từ `pending`, hai nhánh không approve bắt buộc `reason` | — | Registrations |
| `reviewRequests/{id}` | projectId, classId, documentId, currentVersionId, supervisorStatus (`waiting|inReview|approved|needsRevision|notAccepted`), aiStatus, revision, ruleSnapshotRef | Owner | Owner, chỉ chuyển trạng thái hợp lệ, kiểm `revision` | — | Review queue, Workspace |
| `reviewRequests/{id}/versions/{versionId}` (`documentVersions`) | versionNumber, submittedAt, fileName, mime, size, `contentRef` (URL Cloudinary), ruleSnapshotRef | Owner (seed / Web sau này) | — **bất biến** | — | Versions, Workspace |
| `reviewRequests/{id}/feedback/{id}` | documentVersionId, authorUid, message, severity, category, origin, official, evaluationId? | Owner | Owner khi `official == false`; sau khi official thì bất biến | Owner khi chưa official | Workspace, History |
| `reviewRequests/{id}/evaluations/{id}` | documentVersionId, runToken, ruleSetId, ruleSetVersion, status (`loading|completed|error`), criterionResults[], findings[], totalScore?, errorCode? | Owner | Owner: `loading → completed|error`; bản cũ chỉ là lịch sử | — | AI result |
| `reviewRequests/{id}/decisions/{commandId}` | documentVersionId, decision (`approved|needsRevision|notAccepted`), note, selectedFeedbackIds[], actorUid, decidedAt | Owner, id = `commandId` | — **append-only** | — | History |
| `reviewRequests/{id}/audit/{id}` | commandId, actorUid, action, versionId, feedbackIds[], at | Owner | — | — | History |
| `reports/{id}` | reviewId?/projectId?, fileName, url (Cloudinary), size, generatedAt, formatVersion | Owner, **sau** khi upload thành công | — | Owner | Profile, Export |

Ghi chú thiết kế:

- Lab item ID được copy nguyên giữa offering nên **không duy nhất toàn cục**; item luôn nằm dưới offering/class, không có collection `labItems` toàn cục.
- `evaluations` (~12 KB/bản) và `ruleSnapshot` lặp lại nhiều nơi, nên là subcollection hoặc tham chiếu `ruleSnapshotRef`, không nhúng vào doc request.
- `courseCodes`, `classCodes`, `groupNames` là doc dự trữ cho ràng buộc duy nhất. Tạo/đổi tên phải ghi doc dự trữ **trong cùng transaction**; rules kiểm `getAfter` rằng doc dự trữ tương ứng cùng tồn tại.
- Phần dữ liệu trình bày của fixture (`presentation`, `statusMeta`, `groupHealthMeta`, `feedbackCategories`, `documentSamples`, `studentImportSample`, `now`, `currentUser`, `dashboard`) **không** lên Firestore: giữ trong asset hoặc tính ở presentation. `documentSamples` chỉ làm nội dung xem trước, không phải tệp thật.

## 3. Chuyển trạng thái (lấy từ domain đã có)

| Entity | Hợp lệ | Ràng buộc |
|---|---|---|
| ReviewRequest | `waiting → inReview`; `waiting|inReview → approved|needsRevision|notAccepted` | `needsRevision` bắt buộc feedback, `notAccepted` bắt buộc lý do; `supervisorBlock` chặn khi rule không `active` hoặc `aiRequired` mà `evaluation.status != completed` |
| Nộp lại | `needsRevision → waiting`, thêm version v2, **giữ `reviewId`**, cập nhật `currentVersionId` | Không nộp lại từ `waiting|inReview|approved|notAccepted`; không sửa v1 |
| Evaluation | `loading → completed|error`; retry = run mới với token mới | Kết quả của version cũ chỉ là lịch sử, không cập nhật trạng thái hiện tại |
| Feedback | draft → official khi nằm trong `selectedFeedbackIds` **và** đúng version hiện tại | Official bất biến |
| Registration | `pending → approved|changesRequested|rejected` | Approve tạo Project + link nhóm đúng một lần (idempotent theo `commandId`) |

`decideReview` là **một transaction**: kiểm `expectedRevision` và `expectedVersionId`, ghi decision (id = `commandId`) + đánh dấu feedback official + audit + inbox + cập nhật request. Quá 500 thao tác thì giảm fan-out, không tách ngầm.

## 4. Trả lời DEP-01..12 cho phạm vi Lab 3

| ID | Quyết định cho Lab 3 | Để lại cho Final |
|---|---|---|
| DEP-01 | Chỉ owner-only theo `ownerUid`; `users/{uid}.role` không dùng để cấp quyền | Role vocabulary, Admin bootstrap, assignment, bảng CRUD theo role |
| DEP-02 | Bảng §2 là schema; giữ ID fixture khi seed | Ký nhận với Web/Backend |
| DEP-03 | Doc dự trữ `courseCodes`, `classCodes`, `groupNames`; rules + emulator test | Race test hai client thật |
| DEP-04 | §3; decision id = `commandId` | Web tạo v1/v2 thật |
| DEP-05 | `contentRef` = URL Cloudinary (unsigned preset, chỉ PDF, giới hạn dung lượng); mở bằng `url_launcher` | Final cấm Storage, chưa chốt nguồn tệp |
| DEP-06 | Inbox tự ghi trong transaction nghiệp vụ, không Functions; thông báo đẩy gửi từ Firebase Console | Announcements theo audience |
| DEP-07 | F3 demo bằng **seed v1 + nút demo ghi v2** cùng `reviewId`; không có màn Student | Student Web ghi thật |
| DEP-08 | AI mô phỏng, gắn nhãn; bật/tắt bằng Remote Config; không bypass guard `aiRequired` | Firebase AI Logic + App Check |
| DEP-09 | Query lọc/sắp xếp `(updatedAt DESC, id DESC)`, `limit` có chặn, `firestore.indexes.json`; thao tác ghi quan trọng yêu cầu online | Chính sách offline |
| DEP-10 | Project `srs-ai-prm`, package `com.srsAIPrm`; không secret trong repo | App Check, CI cho rules |
| DEP-11 | Làm cả FCM và upload theo Lab 3 (Cloudinary) | Hai checklist Lab 3/Final tách riêng |
| DEP-12 | Không có package dùng chung; DTO/contract thuần Dart đặt trong `lib/core/` | `packages/core` |

## 5. Giới hạn đã biết (ghi thẳng vào báo cáo)

- Security Rules không đếm được request, nên **không có** quota 50/ngày.
- Rules chỉ kiểm hình dạng, không kiểm tổng trọng số rubric bằng 1.0.
- Không có kiểm quote, vì không có LLM thật.
- Một Supervisor = một vùng dữ liệu. Không chia sẻ lớp giữa nhiều giáo viên.
- Audit/inbox do client ghi nên **không** có độ tin cậy ngang audit do server ghi.
