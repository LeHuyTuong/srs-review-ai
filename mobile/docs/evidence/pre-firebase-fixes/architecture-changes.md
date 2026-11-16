# Kiến trúc sau Phase 4.5 và lộ trình Firebase

26/10/2026. Đây là refactor có giới hạn trên project hiện có, không viết lại hệ thống. Supervisor-only Login vẫn giữ nguyên. Không thêm package hoặc SDK Firebase.

## Vòng đời phiên và dữ liệu

| Loại | Owner/lifecycle sau sửa | Ví dụ |
|---|---|---|
| Authenticated identity mock | SessionViewModel; mỗi lần login có object/generation mới | AppSession.role, userId `mock:<email>`, generation |
| Operation lifetime | SessionScope do SessionViewModel sở hữu, sessionScopeProvider công bố; revoke đồng bộ khi logout/login thay thế | Active flag dùng ở VM callbacks và atomic fake commit |
| User-specific client state | Providers watch sessionScopeProvider; rebuild/reset khi scope đổi, widget/navigation dispose theo session key | Dashboard selection, management/class filters/saved maps, form drafts, reader position, AI expansion/error, enrollment picker state |
| Scoped data access handle | academicRepositoryProvider tạo adapter mới theo scope; old handle từ chối cả load và write | FakeAcademicRepository với scope |
| Shared fake server data | academicServiceProvider sống trong root container; chỉ giữ domain mutations đã commit; mất khi app engine/process khởi động mới | Course/Offering/Class/Group/Project/review aggregate |
| Shared application configuration/technical gateway | Giữ provider độc lập session nếu không chứa dữ liệu cá nhân | Theme/assets/device-import gateway factory |
| Persistent backend tương lai | Chưa có; phải authorize bằng verified UID và server policy, không xóa server data khi logout | Firestore/Storage |

Scope có thể không mang userId trong test harness/domain tests hoặc signed-out container. Đây không phải quyền truy cập backend: production app guard vẫn chỉ mount Supervisor UI khi đã có session hợp lệ. Khi có Firebase phải thay mock bằng auth-state/verified UID, không dùng email nhập từ form làm bằng chứng quyền sở hữu.

Lần đầu implementation thử đọc scope provider ngược từ SessionViewModel.signOut đã bị targeted test phát hiện CircularDependencyError; đã đổi sang session notifier sở hữu/revoke token trực tiếp, provider chỉ expose token. Bản cuối không có dependency vòng mới và toàn bộ tests PASS. Không che kết quả thử nghiệm này.

## Async isolation

`FakeAcademicService.commit` chờ load xong, kiểm tra scope active và expected revision, validate uniqueness rồi publish snapshot trong cùng đoạn đồng bộ. Operation cũ không vượt qua việc revoke nếu chưa đến commit boundary. Commit đã hoàn tất trước logout vẫn là shared data hợp lệ, không bị xóa ngược.

`AcademicViewModel.mutate` giữ scope gốc và chỉ publish UI/invalidate Dashboard khi scope đó còn active. AI run giữ scope qua khoảng chờ mô phỏng và kiểm tra lại trước mutation kết quả; form/file-picker/enrollment/AI-panel callbacks không đưa dữ liệu hoặc lỗi trễ vào state của phiên mới. AsyncNotifier tự loại future load đã bị supersede; scoped repository cũng kiểm tra active sau await load.

App MaterialApp key theo session tạo lại protected navigation/PageStorage khi identity đổi hoặc logout, thay vì chỉ phủ Login lên stack còn sống. Bộ lọc Dashboard giữ qua mutation và retry trong cùng scope; khi scope đổi, selection khởi tạo mới. Saved maps được clear khi notifier rebuild, không chỉ đổi immutable state rồi để field mutable cũ tồn tại.

## ID và transaction invariants

- Course code là giá trị nghiệp vụ uppercase/trim; internal ID mới độc lập code. Legacy IDs không migrate, nên toàn bộ references có sẵn không đổi.
- CourseDto kiểm tra shape/types/nonempty ở data edge; unknown fields được deep-freeze/copy và giữ khi update. AcademicSnapshotCodec chỉ là **bước đầu**, kiểm tra root/courses, không tuyên bố đã validate schema của mọi entity.
- CourseMutation phân biệt create/update. Create collision không chuyển thành upsert; edit phải tìm thấy entity. Uniqueness chạy trước ghi và tại fake command/commit boundary. Expected revision bảo vệ optimistic concurrency, thất bại không publish snapshot.
- FakeAcademicRepository hỗ trợ thêm CourseCommandRepository. Academic VM dùng typed seam nếu adapter hỗ trợ; legacy snapshot repository vẫn dùng cho các workflows chưa migrate và test adapters. Contract typed mới được dùng trong đường chạy app mặc định, không chỉ là interface để đó.
- Service chỉ tham chiếu module contract thuần dữ liệu, không phụ thuộc repository implementation hoặc UI. Chưa tách toàn bộ domain/DTO khỏi raw-map legacy để tránh refactor rộng. Import SCC check không có vòng mới; ba SCC legacy còn nguyên.

## Shared projections

`resolveProjectClassId(groupClassId, directClassId)` là nguồn quy tắc dùng chung ở management query và Dashboard. Group đang liên kết là authoritative; khi detach, direct classId còn hợp lệ là fallback. Không phục hồi Group đã xóa hoặc sửa dữ liệu review lịch sử để bù thống kê.

`AcademicProjections` cung cấp semester phase/order, grouped-visible-student count và enabled criterion total. `ProjectDocumentProjection` cung cấp tab counts/visible priority-order, không mutate input. VM expose các giá trị này cho View. Layout, responsive constraints, date formatting và lặp render widget vẫn nằm ở View. Các legacy projection khác không thuộc finding cụ thể chưa được refactor đồng loạt.

## Lộ trình migration cụ thể — chưa triển khai

| Bước | Thay contract nào | Invariants/evidence bắt buộc trước chuyển |
|---|---|---|
| 1. Auth/ownership | Google Sign-In adapter và auth-state→verified UID; session identity thay mock userId | Signout revoke/reset như hiện tại; server policy xác định Supervisor được đọc/ghi lớp/môn/review nào; không suy ra quyền từ tên actor hoặc email input |
| 2. Scoped query | Dần thay whole `load()` bằng query theo Supervisor UID/semester/class, typed page/cursor và subscription disposal | Mỗi route có loading/empty/permission/network/retry; query scope không cho đọc chéo ngoài quyền. Giữ resolver Project context chung |
| 3. Course typed write | Chuyển CourseCommandRepository sang transaction Course + normalized-code uniqueness index, dùng stable server IDs | Create/update semantics, unique index và expected entity version kiểm tra server-side atomically; không upload whole snapshot; tests collision/race hiện có tái dùng |
| 4. Offering/Class/Enrollment/Group | Typed DTO và atomic workflow commands theo từng aggregate | Enrollment capacity, member limit, one project/group, class ownership và derived counts cập nhật cùng transaction; không lần lượt ghi từng document thiếu atomicity |
| 5. Review | Typed review/version/rule-snapshot/feedback/audit commands | Immutable history, đúng document/version/evaluation token, selected feedback, authorization quyết định, expected version; server validation không chỉ client |
| 6. Error/transport mapping | Map exceptions thành domain code, service reporter riêng | Hiện mới taxonomy + errors mới; bổ sung permissionDenied/offline/network/cancel/reporting thật khi có adapter, giữ thông điệp UI an toàn |
| 7. Report/file/services | Exporter + file gateway, Storage/FCM/Analytics/Crashlytics/Remote Config adapters | Workflow Supervisor tạo report, path theo UID/progress/cancel; payload route qua auth; typed non-PII events; remote config defaults. Không thêm Student Mobile |

Mỗi bước chuyển một workflow có compatibility tests, sau đó mới loại legacy contract của workflow đó. Whole-snapshot `AcademicRepository.commit` **không** là API Firestore tương lai. Revision aggregate hiện tại không chứng minh transaction nhiều người dùng, pagination, subscriptions hay offline sync đã sẵn sàng. Ownership/access-rule chưa được quyết định trong phase này; không tạo policy hoặc role mới tùy ý.

## Kết luận readiness

Nhóm A ổn định hơn và có regression coverage; các projections được yêu cầu đã về đúng layer. Có thể bắt đầu bước thiết kế/tích hợp auth và một lát cắt data nhỏ theo kế hoạch khi có policy/project cần thiết. Chưa nên thay fake service bằng Firestore toàn snapshot hoặc gọi toàn ứng dụng READY. Firebase/ARTEMIS/export và các submission gates của Final Audit vẫn còn.
