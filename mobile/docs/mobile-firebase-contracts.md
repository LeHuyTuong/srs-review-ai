# Phase 5.0 - Contracts cần thống nhất cho Supervisor Mobile

Ngày: **26/10/2026**, Asia/Saigon. Đây là **đề xuất contract để nhóm Mobile/Web/Backend review**, chưa phải schema/rules/API đã được thống nhất hoặc triển khai. Không cấu hình Firebase, thêm SDK, deploy rules hay sửa Web trong phase này.

## 1. Boundary hiện tại và nguyên tắc chuyển đổi

| Boundary hiện có | Source | Hạn chế |
|---|---|---|
| `AcademicRepository.load()/commit(next, expectedRevision)` | `lib/repositories/academic/academic_repository.dart` | Load/ghi toàn AcademicSnapshot; chỉ phù hợp fake/compatibility, không phải API production |
| `CourseCommandRepository.commitCourse(CourseMutation, expectedRevision)` | `lib/repositories/academic/course_contract.dart` | Typed seam đã dùng thật nhưng vẫn trả snapshot và aggregate revision; CourseDto mới validate một lát cắt |
| `DashboardRepository.load()` | `lib/repositories/dashboard/dashboard_repository.dart` | One-shot, chưa scope/query/realtime |
| `NotificationRepository.load()` | `lib/repositories/notification_repository.dart` | Trả AcademicRecord từ asset; contract/adapter/provider đang cùng file, lọc title bằng regex; chưa stream/read state |
| `StudentDeviceGateway.pick()/copy()` | `lib/repositories/academic/student_device_gateway.dart` | Native CSV/clipboard, không phải Student upload hay Firebase transport |
| Session/operation token | `lib/app/session.dart`, `lib/models/session_scope.dart` | Mock identity, revoke local; không thay auth/rules |

Giữ screens -> VM -> repository contract -> service/SDK. DTO codec chuyển Firestore values sang model thuần Dart ở data layer; không lộ DocumentSnapshot/Timestamp/FirebaseException vào View hoặc VM. Tách typed commands theo nghiệp vụ, không serialize snapshot toàn app thành một Firestore document. Không tạo custom server/Cloud Functions để lách giới hạn Final.

## 2. Quy ước dữ liệu chung cần ký nhận

| Mục | Đề xuất | Cần nhóm xác nhận |
|---|---|---|
| Identity | Auth UID bất biến là actor/owner; `users/{uid}.role`; studentId học vụ là ID riêng | Role string `supervisor` hay alias `staff`; map student UID <-> studentId; Admin bootstrap và gán lớp |
| Role admission | Mobile chỉ Supervisor; Admin/Student/wrong role báo rõ và không mount protected routes | Authenticated nhưng chưa có profile/role dùng trạng thái chờ/từ chối, không tự mặc định Supervisor; role revoke xử lý thế nào |
| Entity ID | ID ổn định độc lập mã/name, không đổi khi sửa code; tham chiếu bằng ID | Giữ legacy fixture ID khi seed hay dùng mapping migration; không migrate ngầm references |
| Business code | Course code trim+uppercase; khóa unique `courseCodes/{normalizedCode}` hoặc key tương đương | Uniqueness global hay theo tổ chức; đổi code release/acquire index trong cùng transaction; rules bảo vệ index |
| Time | UTC timestamp persisted; UI format tiếng Việt sau mapping | serverTimestamp/create/update timestamps; date-only semester/deadline timezone Asia/Saigon và biên ngày |
| Version | `schemaVersion` cho schema, `revision` mỗi entity; DocumentVersion và RuleSet version riêng | Không dùng global AcademicSnapshot.revision làm lock cả hệ thống; field bắt buộc và expectedRevision trên command |
| Unknown fields | Read codec tương thích có giới hạn; update patch allowlisted, không round-trip tùy ý field từ JSON | Không để preserve-unknown legacy vô tình ghi field role/owner/status bị cấm; schema migration/fallback |
| Types/null | Typed enums, ID nonempty, int limits, finite scores, nullable fields explicit | Unknown enum/type -> invalidData, không fallback thành approved; decimal score precision và max sizes |
| Query page | Stable sort `(updatedAt DESC, id DESC)`, opaque cursor + limit bounded | Composite indexes, query ownership filter, null/missing timestamps và refresh/reorder semantics |
| Concurrency | CommandId/idempotency key + expected entity/version IDs; transaction cho các liên kết | Retry chỉ với command id cũ; audit/notification không nhân đôi. Online-only decisions hay offline queued commands? |
| Delete/archive | Archive ưu tiên, lịch sử/version append-only; không cascade xóa review khi detach Group | CRUD per role, retention và quy tắc restore; uniqueness 1 active project/group |
| Authorization | Scope theo Supervisor UID và assignment thật; deny-by-default | Scope tổ chức/class/project/review; quyền quản lý global Semester/Course/Rule không tự suy từ UI fake |

UI hiện dùng `currentUser.name` làm actor và thời gian dạng chuỗi hiển thị trong review actions. Đây là **debt mapping**: server data dùng `actorUid`/timestamp; display name chỉ là presentation được phép đọc. Không sử dụng tên/email hoặc role client gửi để chứng minh quyền.

## 3. DTO và Firestore collection draft

Các collection dưới đây là **tên đề xuất**; Backend có thể chọn nested paths nhưng phải giữ invariants, scope/query và mapping rõ. `id` lấy từ document path; các entity mutable thường có `schemaVersion:int`, `revision:int`, `createdAt/updatedAt:timestamp`, `createdBy/updatedBy:uid`. Rules cần validate required/allowed keys, type, range và field bất biến. Không đưa byte PDF hoặc list toàn trường/lớp vào một document duy nhất.

| DTO / collection dự kiến | Fields cốt lõi / quan hệ | Mobile dùng tại | Quyền/điểm cần chốt |
|---|---|---|---|
| UserProfileDto `users/{uid}` | role:enum, displayName:string, active:bool | Session, Profile, actor label | Self read; Admin đổi role; policy self-create không cho tự nhận Supervisor; profile nhạy cảm giới hạn theo vai trò |
| SupervisorAssignmentDto `supervisorAssignments/{id}` | supervisorUid, classId, active | Mọi scoped query/command | Admin/Staff được chỉ định quản lý, Supervisor read own; cần phương án rules kiểm tra assignment |
| SemesterDto `semesters/{id}` | name, academicYear, startDate/endDate, archived | Semester, Dashboard | Supervisor read theo policy; quyền create/update/archive global chưa chốt |
| CourseDto `courses/{id}` + CodeReservationDto `courseCodes/{code}` | code, name, archived; reservation.courseId | Courses, detail, Offering | Quyền global và code uniqueness; không map code thành internal ID |
| OfferingDto `offerings/{id}` | courseId, semesterId, status, defaultRuleSetId, labStructureVersion | Offering, Class, F1 | Scope theo assignment; quyền thay cấu trúc và ảnh hưởng lớp hiện hữu |
| LabStructureDto `labStructures/{id}` | offeringId/classId scope, version, labs/items/dependency IDs, rule assignments | Offering/override, Project labs | Immutable revision/snapshot hoặc docs items riêng; giới hạn kích thước/rules; Class override ưu tiên |
| ClassDto `classes/{id}` | offeringId, name/code, state, capacity, groupMemberLimit, labOverrideRef? | Classes, F1 | Supervisor chỉ lớp được phân công; không giảm limits dưới occupancy; update liên kết cần transaction |
| StudentDto `students/{id}` + EnrollmentDto `enrollments/{id}` | student.uid?, academicCode, displayName; enrollment.classId/studentId/state | Directory, Class students/import | PII chỉ trong scope; enrollment unique (classId,studentId), capacity atomic; Admin/Web là owner của hồ sơ nào? |
| JoinCodeDto `classJoinCodes/{id}` (nếu giữ QR) | classId, code, expiresAt, revision, active | Supervisor regenerate/copy QR | Không dùng ngày expiry hard-coded; access/rotation/rate limits do team chốt; không public danh sách mã |
| GroupDto `groups/{id}` | classId, name, memberIds hoặc membership refs, projectId? | Groups, Class, F1 | Unique tên theo lớp, đúng lớp/limit; nhóm lớn cần membership docs; 1 active project |
| ProjectDto `projects/{id}` | classId, groupId?, name, state, labSnapshotRef, member snapshot/ref | Project, Dashboard | Gắn group nguyên tử, detach giữ direct classId hợp lệ; quyền khi archive/restore |
| RegistrationDto `projectRegistrations/{id}` | groupId/classId, submitterUid, status, reason?, projectId? | Registrations, Web queue nếu chọn | Chốt role quyết định; pending -> approved/changesRequested/rejected như fake hiện tại; approve tạo Project/link đúng một lần |
| RuleSetDto `ruleSets/{id}` + revision snapshot | name, version:int, active, aiEnabled, aiRequiredBeforeSupervisor, criteria, thresholds, allowedFormats | Rule library, review | Ai quản trị shared rules; snapshot đúng version gắn submission/review; không sửa history theo rule mới |
| DocumentDto `documents/{id}` | projectId, labItemId, title, currentVersionId, availability/status | Documents, reader | Document identity khác filename; scope theo project/class; không gộp document status với AI/decision |
| DocumentVersionDto `documentVersions/{id}` | documentId, reviewId, versionNumber:int, submittedByUid, submittedAt, fileName/mime/size/hash, contentRef, ruleSnapshotRef | Workspace, Versions, F3 | Web create; submitted version immutable; file transport chưa chốt theo §7 |
| ReviewRequestDto `reviewRequests/{id}` | documentId/projectId/classId, currentVersionId, supervisorStatus, aiStatus, revision, ruleSnapshotRef | Queue, Workspace, Dashboard | Một logical reviewId qua v1/v2; trạng thái phải có enum mapping; assignments validate cả reads/writes |
| FeedbackDto `feedback/{id}` | reviewId, documentVersionId, authorUid, message, severity/category, origin, official, evaluationId? | Workspace/history, Web feedback | Draft editable theo owner/policy; chỉ feedback cùng currentVersion được chọn official khi decision; official immutable |
| EvaluationDto `evaluations/{id}` | reviewId/documentVersionId, runToken, ruleSetId/version/snapshotRef, model/configVersion, status, criterionResults, findings, scores, errorCode? | AI result/history | Schema Level 2, stale token handling, retry tạo run mới; client AI output không phải dữ liệu đáng tin để tự cấp quyền |
| ReviewDecisionDto `reviewDecisions/{id}` | commandId, reviewId, documentVersionId, decision, note/reasonCode?, selectedFeedbackIds, actorUid, decidedAt | History, Web result | Append-only, một quyết định hợp lệ/version; no overwrite. Atomic request/feedback/audit/notification khi cần |
| AuditEventDto `auditEvents/{id}` | commandId, actorUid, action, entityId/reviewId, versionId, feedbackIds, timestamp | Review history/index | Append-only, rules validate actor/time/transition. Client-created log không tự có mức tin cậy server audit; nêu giới hạn trong report |
| AnnouncementDto `announcements/{id}` | title/body, audienceRole/classIds, status, publishedAt, authorUid, destination? | Notifications/inbox | Web được ủy quyền publish; Mobile read đúng audience; scheduled/archived behavior cần chốt |
| InboxNotificationDto `users/{uid}/inbox/{id}` + ReceiptDto | kind, entityId/reviewId/versionId, announcementId?, createdAt; readAt? | Notifications, F3 | Chốt personal inbox hay query announcements + `announcementReceipts`; ai tạo decision notifications khi không Functions; không regex theo title |
| ReportMetadataDto `reports/{id}` | ownerUid, reviewId/projectId, versionId, filters/scope, generatedAt, mime/size/hash, formatVersion | Export/Profile | Final chỉ metadata, không upload binary/base64; không coi đường dẫn local Android là URL chia sẻ cho Web |

Dashboard nên dùng scoped summaries/aggregation hoặc projection được phép đọc, không đọc toàn trường rồi lọc trên client. Derived counts phải có nguồn chuẩn: query aggregation hoặc transaction updates có rules, tránh client ghi count tùy ý. Backend quyết định representation và index; Mobile giữ resolver Group.classId -> Project.classId fallback đã sửa.

## 4. Repository interfaces đề xuất (chưa có source)

Tên dưới đây dùng để bàn giao. Mỗi query cần `SupervisorScope` từ verified session, filter typed, page limit/cursor; mỗi mutation trả entity/revision/receipt cần thiết, không trả toàn bộ AcademicSnapshot. SDK gọi trong service/adapter; contract/model thuần Dart để có thể đưa vào shared package về sau.

| Interface đề xuất | Read/query | Commands / tính nhất quán |
|---|---|---|
| AuthSessionRepository | `watchSession()`, `loadRole(uid)` | Google sign-in/cancel/sign-out; không nhận role/email làm proof; session state loading/authenticated/denied/signedOut/error |
| AcademicCatalogRepository | watch/list/get Semester/Course/Offering/RuleSet/LabStructure theo quyền | Typed create/update/archive/assign-rule/clone-lab; Course code reservation atomic |
| ClassRosterRepository | class/enrollment/student pages, class detail stream | Enroll batch validate toàn batch; limits/unique membership/QR rotation; transaction không partial enrollment |
| GroupProjectRepository | group/project pages/detail | Create/rename group, members, create/assign project, detach/archive; kiểm tra 1 active project/group cùng transaction |
| ProjectRegistrationRepository | scoped pending list/detail | Approve/reject với expectedRevision, reason, commandId; idempotent project/link creation |
| DocumentRepository | document/version list/detail, file availability | Read-only submitted versions từ Mobile; device reader gateway xử lý contentRef qua policy đã chốt |
| ReviewRepository | `watchQueue(query)`, `watchReview(id)`, versions/feedback/audit pages | `startReview`, `saveDraftFeedback`, `decideReview(reviewId, expectedVersionId, expectedRevision, decision, selectedFeedbackIds, note, commandId)`; immutable history |
| AiEvaluationRepository / AiGateway | evaluation by version, current run | `evaluate` với sanitized input, config, versionId/token; validate structured result, user edit/accept; không auto decide |
| DashboardRepository phiên bản scoped | `watchSummary(scope, semesterId)` | Read-only; loading/error/empty/source metadata; selection là VM state theo session |
| InboxRepository | `watchAnnouncements(scope)`, `watchPersonalInbox(uid)`, read receipts | `markRead` own receipt; deep link typed+authorized; retry không nhân notification |
| ReportRepository + DeviceReportGateway | metadata list/get | Generate PDF từ snapshot nhất quán + save/share local; metadata write sau generate thành công; Storage gateway tách riêng nếu Lab 3 cần |
| ConfigurationRepository / TelemetryGateway | typed defaults + fetched config, fetch provenance | Activate validated RC; analytics events/nonfatal reporter qua DI, không chặn workflow nếu telemetry lỗi |

Tách interface không bắt buộc tạo từng interface ngay trong một lần refactor. Ưu tiên Course/auth rồi một flow review; giữ compatibility adapter và fake tests khi migrate từng lát cắt.

### Error/result contract

Giữ codes hiện có `validation/conflict/sessionExpired/invalidData/permissionDenied/notFound`; đề xuất bổ sung `unauthenticated`, `cancelled`, `networkUnavailable`, `deadlineExceeded`, `quotaExceeded`, `unavailable`. SDK error -> domain error kèm safeMessage, retryability và operationId; stack/debug details chỉ vào reporter không chứa PII. User-cancel không báo crash. Error giữ draft/current version; permission/role-revoked đóng quyền truy cập và làm sạch dữ liệu đang hiển thị.

Stream result cần phân biệt initial loading, empty, data, error; data có metadata `fromCache`, `hasPendingWrites` hoặc biểu diễn tương đương thuần Dart để UI không tuyên bố server đã nhận khi mới ghi local. Chốt có cho offline draft/command hay không; với decisions đề xuất online confirmed-only để tránh phê duyệt stale version. Firestore offline transaction failure phải có message/retry, không giả lập thành success.

## 5. Status transitions và atomic writes cần bảo vệ

| Entity/track | Transition đề xuất từ nghiệp vụ hiện hành | Actor / guards |
|---|---|---|
| Logical ReviewRequest | First submit -> `waiting`; `waiting -> inReview`; `waiting/inReview -> approved/needsRevision/notAccepted` nếu policy hiện hành cho phép | Web tạo lần đầu, Supervisor được assign quyết định; Rule Set Active/AI prerequisite/current version/expectedRevision |
| Resubmit | `needsRevision -> waiting`, append DocumentVersion v2+, update currentVersionId, **giữ reviewId** | Web Student đúng owner/membership. Không resubmit từ waiting/inReview/approved/notAccepted; không sửa v1 |
| AI evaluation | New run `loading -> completed/error`; retry = run mới, token mới | Supervisor; đúng current version và rule snapshot; kết quả bản cũ chỉ lịch sử, không update current state |
| AI request projection | Fixture dùng `notRun/aiReviewing/aiReviewed` | Phải map riêng với evaluation.status; không dùng cùng enum với supervisorStatus/documentStatus |
| Feedback | Draft -> official khi nằm trong selectedFeedbackIds đúng version | needsRevision bắt buộc feedback; notAccepted bắt buộc lý do; “Khác” cần ghi chú theo policy; approved note optional |
| Decision/history | Append decision + official feedback + audit; request terminal cho version đó | actorUid = auth UID; idempotency; lịch sử không update/delete; two reviewers race chỉ một thắng |
| Registration | pending -> approved/changesRequested/rejected; hai nhánh không approve bắt buộc feedback | Role quyết định phải được nhóm chốt; approve + Project + Group link nguyên tử; đường sửa/nộp lại từ changesRequested do Web/Backend thống nhất, Mobile hiện không tự reset pending |
| Project/group | Create/assign/detach/archive/restore theo policy | Active class, capacity, member scope; detach không xóa Project.classId hoặc review history |
| Announcement | draft -> published -> archived | Role Web được ủy quyền; audience immutable hay re-target có version phải chốt |

Backend phải chứng minh các transaction/batch được rules validate bằng `getAfter` hoặc cơ chế phù hợp, kiểm tra giới hạn số document/rules reads và payload kích thước trước khi duyệt thiết kế. Nếu một batch review/notification fan-out quá lớn, giảm mô hình fan-out hoặc dùng audience query + receipt, không tự thêm Functions. Client UI guard không thay rules; AI result do client ghi không được coi là bằng chứng server đã chạy AI. Team phải ghi threat model và chốt cách xử lý `aiRequiredBeforeSupervisor` trong kiến trúc không custom server.

## 6. Quyền, query/index và lifecycle acceptance

Đề xuất tối thiểu: Supervisor chỉ đọc lớp/project/review được assign, ghi review decision/feedback trong scope, đọc profile của mình, đánh dấu own receipt và tạo own report metadata. Student chỉ tạo/resubmit version thuộc project của mình và đọc official feedback; Admin quản lý roles. Quyền ghi catalog/global rules/announcements/registrations **chưa thống nhất**, không mặc định trao cho Supervisor từ fake UI.

Backend trả collection/path và index manifest cho: assignments theo supervisorUid; classes theo semester/offering; projects theo class/state; review queue theo class/semester + supervisorStatus + updatedAt/id; versions theo reviewId/versionNumber; official feedback theo reviewId/versionId; audit theo reviewId/time; announcements theo audience/status/publishedAt; inbox theo uid/readAt/createdAt. Rules không phải bộ lọc: query phải đáp ứng điều kiện quyền ngay trên server. Scope gồm nhiều class/role có thể cần nhiều bounded queries; chốt merge/pagination và giới hạn trước khi giữ hành vi All filters như fake.

Logout/role change phải cancel listeners, revoke operation scope, hủy navigator/drafts/filters/reader/AI state, xóa identity khỏi telemetry và không publish callback cũ. Giữ dữ liệu backend đã commit. Với persistent Firestore cache/pending writes: chốt cơ chế sign-out, cache cleanup khi đổi tài khoản, listener detach và acknowledgment trước revoke; local token **không thể thu hồi một write đã gửi lên server**. Tests phải phân biệt write đã commit trước logout với command chưa gửi, write đang pending và event đến muộn; rules theo auth mới là boundary bảo mật.

## 7. File/report, AI và instrumentation

**File gate:** Final p.3 cấm Cloud Storage và chỉ quy định PDF report local/share + metadata Firestore. Lab 2 F3 vẫn có Student nộp tài liệu cần Mobile đọc được. Nhóm phải chọn representation/content source được giảng viên chấp thuận, giới hạn mime/size, cách authorize contentRef, revoke/expired/missing handling và seed tài liệu thật. Không tự đưa file bytes/base64 lớn vào Firestore, không giả định external public URL đã được cho phép, không coi sample reader hiện tại là đọc tài liệu thật. Chưa chốt file contract thì chưa thể đóng F3/reader gate.

**Report gate:** PDF phản ánh đúng scope/filter/current version của Supervisor, generatedAt và report format version; cancel/save/share failure có feedback; Firestore metadata không được ghi success nếu generate thất bại. Nếu Lab 3 được nghiệm thu riêng bằng Storage thì dùng gateway per-user `reports/{uid}/{reportId}.pdf`, upload progress/cancel/download URL và owner-only rules; không mang nhánh này vào bản Final khi chưa có quyết định.

**AI gate:** Gemini qua Firebase AI Logic + App Check; RC chứa `ai_enabled:bool`, `ai_model:string`, `ai_prompt_template:string` (tên đề xuất), defaults an toàn, validate model/prompt/config version. Đề xuất thêm `review_page_size:int` bounded để đáp ứng ≥2 giá trị thay đổi hành vi mà không đổi business approval thresholds. Prompt chỉ nhận nội dung học thuật đã loại PII và rule criteria; không names/emails/photos; cần rà cả PII trong nội dung file/feedback/log. JSON response validate criteria IDs, severity enum, scores/ranges, findings và version binding. Output có nhãn AI, editable/accept trước official; user acceptance không đồng nghĩa Supervisor approval. AI off/quota/network có fallback theo policy thống nhất, không bỏ AI-required guard ngầm.

**Event proposal** (chưa `docs/analytics-plan.md` chính thức, chưa ghi DebugView):

| Event | Trigger / parameters typed không PII | Flow / câu hỏi |
|---|---|---|
| login / logout | successful auth: method:string; logout không params | Session: vào/ra bao nhiêu lần? UID qua API identity riêng, không email |
| search | entity_type:string, result_count:int, query_length:int; không raw query | F1/F2: tìm kiếm nào không có kết quả? cần search_term thì sanitize/allowlist trước |
| view_course / view_class / view_group / view_project | entity_id:string | F1: rời ở chi tiết nào? |
| view_document / view_review / view_version / view_review_history | entity_id:string, version_id:string khi có | F2/F3: đọc đúng version/lịch sử trước quyết định không? |
| create_project | project_id:string, source:string | F1: bao nhiêu lần hoàn thành tạo Project? |
| review_decision | review_id:string, version_id:string, decision:enum | F2/F3: loại quyết định và tỷ lệ hoàn thành? |
| export_report | report_id:string, file_size_kb:int, export_target:enum | Export: tạo/chia sẻ thành công bao nhiêu? upload event chỉ khi nhánh Lab 3 có thật |
| ai_request / ai_result_accepted / ai_error | review_id/version_id, model/config_version:string, error_code:enum khi lỗi | Final AI: retry/fallback và acceptance ra sao? Không log prompt/output |
| announcement_open | announcement_id:string, source:enum | Inbox/cross-role: thông báo có được mở không? |

Đủ hơn 7 events nhưng phải hợp nhất vào event plan chính thức có trigger/type/question/flow; bổ sung events cho mỗi loại detail thực tế khi implement. Crashlytics: một lỗi thật nonfatal (ví dụ permission/network đã xử lý) và test crash, UID + key an toàn như operation/config_version, không nội dung file/email. Analytics/Crashlytics lỗi không làm hỏng decision transaction. FCM Lab 3 nếu triển khai cần permission lifecycle, token refresh/unregister, foreground/background/terminated routing, dedupe và auth-gated typed destination; không tin route tùy ý trong payload.

## 8. Danh sách dependency cần nhóm trả lời

| ID | Câu hỏi/đầu ra phải thống nhất | Owner chính | Chặn bước nào |
|---|---|---|---|
| DEP-01 | Role vocabulary, users bootstrap, Supervisor assignment và global CRUD matrix | Backend + Web + Mobile | Auth và mọi scoped query |
| DEP-02 | Collection paths, DTO schema/enums/null/version/time, legacy ID seed mapping | Backend chủ trì, hai clients ký nhận | Tất cả repositories |
| DEP-03 | Atomic Course unique code, enrollment/group/project invariants và allowed/denied rules tests | Backend | Migration F1 |
| DEP-04 | Review/version/ruleSnapshot/feedback/decision/idempotency schema và actorUid | Backend + Web + Mobile | F2/F3 quyết định đúng version |
| DEP-05 | Final không Storage nhưng tài liệu F3 lấy ở đâu; report local vs Lab 3 upload | Nhóm + giảng viên | Reader/export và nghiệm thu hai bài |
| DEP-06 | Announcements audience/read receipt/deep link, decision notification producer không Functions | Web + Backend | Realtime inbox/F3; Mobile không publish announcement thay Web |
| DEP-07 | Chọn F3 làm cross-role được chấp thuận? Web queue item Mobile gửi là nghiệp vụ nào? Student/Web roles | Nhóm + giảng viên | Final cross-role/Web rubric |
| DEP-08 | AI structured schema, sanitization, AI-required fallback/trust model, RC defaults/ownership | Nhóm AI/Backend + Mobile | AI feature Level 2 |
| DEP-09 | Bounded queries/indexes/aggregation/paging và online/offline/cache policy | Backend + hai clients | Scale, concurrency, session safety |
| DEP-10 | Firebase project/app IDs/env, demo accounts/seed, App Check setup, emulators/rules CI evidence | Backend | Tích hợp thật giai đoạn sau; không gửi service-account/API secrets vào repo |
| DEP-11 | Lab 3 FCM và Storage nghiệm thu riêng hay được thay thế theo Final | Nhóm + giảng viên | Chốt danh sách dịch vụ, không tự đánh dấu N/A |
| DEP-12 | Shared Dart package ownership/API version và thời điểm bàn giao, không monorepo hiện tại | Nhóm | Final shared-package criterion |

Trạng thái toàn bộ DEP: **OPEN, chưa có phản hồi xác nhận trong phase này**. Mobile có thể chuẩn bị DTO/fake compatibility ở phase sau trong phạm vi đã được giao, nhưng không nối Firebase hoặc tuyên bố contract đã agreed khi các mục blocking còn mở.
