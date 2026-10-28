# Mapping React UI → Flutter — SRS Review AI

Ngày đối chiếu: 24/10/2026. Tất cả đường dẫn React bên dưới tính từ `D:/UI AI Review` (chỉ đọc). Đây là bản thiết kế chuyển đổi, chưa triển khai widgets/screens.

## 1. Nguồn và thứ tự đối chiếu

- Entry thực tế: `src/main.tsx` → `src/app/App.tsx`; router: `src/app/router.tsx`.
- Token đang dùng: `src/index.css`; cần đọc CSS được import và CSS của từng screen, đặc biệt `src/styles/content-cleanup.css`, `review-refinement.css`, `phase-two.css`, `filter-refinement.css`, `student-refinement.css`.
- Layout Supervisor: `src/layouts/MobileAppLayout.tsx`, `src/components/layout/{MobileHeader,BottomNavigation,SideNavigation}.tsx`.
- Handoff Lab 2: `design-system.md`, `flutter-handoff.md`, `ux/final-ui-spec.md`, `ux/prototype-spec.md`.
- `docs/flutter-handoff.md` còn placeholder và dùng bộ mã S01–S14 khác `ux/final-ui-spec.md`. Dùng route + tên component làm khóa mapping, không ghép theo mã S một cách máy móc. Đường dẫn `app/src/...` trong tài liệu cũ thực tế là `src/...` ở repo này.
- Chưa có đề/rubric Lab 3 riêng trong các tài liệu đã tìm thấy. Kế hoạch Lab 3 đi kèm là đề xuất triển khai từ handoff hiện có, không phải xác nhận đáp ứng rubric chưa được cung cấp. Chưa đối chiếu trực tiếp Figma hay render React trong trình duyệt.

## 2. Design tokens

Từ `src/index.css` (`@theme`):

| Token | Giá trị | Flutter dự kiến |
|---|---|---|
| brand / brand-soft / brand-tint | #146B55 / #EAF4ED / #F2F7F3 | primary + ThemeExtension |
| brand-hover | #105945 | trạng thái pressed/hover của nút |
| ink / muted | #24332D / #66736D | onSurface / chữ phụ |
| line / canvas / subtle | #E1E7E3 / #FAFBFA / #F7F9F7 | outline / scaffold background / nền phụ |
| olive / olive-soft | #637344 / #F1F4E9 | cặp màu trạng thái |
| amber / amber-soft | #756534 / #F5F2E7 | cặp màu trạng thái |
| rust / rust-soft | #A65335 / #FBF0EA | cặp màu trạng thái |
| danger / danger-soft | #A34343 / #FAEEEE | error / error container |
| font-sans | Inter | font asset cục bộ, khai báo đủ weight khi chuyển đổi |

Không chỉ gọi `ColorScheme.fromSeed` rồi mặc định màu đã khớp: gán tường minh các màu và trạng thái component để tránh Material tự đổi palette/tint.

| Đặc tính | Nguồn và giá trị | Flutter dự kiến |
|---|---|---|
| Body | `index.css`: 14, line-height 1.45 | TextStyle(fontSize: 14, height: 1.45) |
| Heading hiện tại | `PageHeading.tsx`: 26/600, height 1.18 | text style riêng; không thay bằng 22/700 từ handoff cũ |
| Chữ nhỏ | `content-cleanup.css`: 10–13px được nâng thành 14 trong `.mobile-app` | đối chiếu effective style, không copy utility class riêng lẻ |
| Spacing handoff | 4/8/12/16/24/32/48 | hằng spacing + SizedBox/EdgeInsets |
| Page padding | layout: ngang 20, trên 12, gap 16 | EdgeInsets + slivers/list |
| Card | `Card.tsx`: radius 12, padding 16, gap 12, viền line | DecoratedBox/Container; không tự thêm elevation |
| Button | `Button.tsx`: min 48×48, radius 8, chữ 14/600; disabled opacity .5 | ButtonStyle + constraints + loading indicator |
| Modal | `Modal.tsx`: mobile bottom sheet, radius trên 12, max-height 92%; desktop dialog max-width 520 | showModalBottomSheet / Dialog, có SafeArea và cuộn |
| Header | `index.css`: min-height 56 mobile, 64 desktop | AppBar/custom toolbar + SafeArea |
| Navigation | 5 tab; item min-height 48 + padding; handoff cũ ghi 64 | custom NavigationBar theme/layout; đo chiều cao thực trước khi cố định |
| Radius/shadow handoff | 6/8/12/16/999; shadow (0,1,2,.06), (0,2,8,.08), (0,8,24,.12), màu ink | BorderRadius/BoxShadow chỉ ở component thực sự sử dụng |

Các sai khác code–handoff trên phải giữ trong checklist đối chiếu, không tự thay đổi thiết kế để đồng nhất tài liệu. Khi cần chọn giữa hai phiên bản thiết kế, chốt baseline trước khi viết UI. Nội dung tiếng Việt, icon, trạng thái và thứ tự thao tác giữ theo source.

## 3. Components → widgets

Các tên Flutter là đề xuất, chưa phải file đã tạo.

| React source | Flutter dự kiến | Điều cần giữ |
|---|---|---|
| MobileAppLayout / MobileHeader | SupervisorShell + Scaffold + SafeArea | header/nav cố định, phần thân cuộn |
| BottomNavigation / SideNavigation | AppBottomNav / NavigationRail hoặc sidebar riêng | 5 tab: Tổng quan, Dự án, Đánh giá, Thông báo, Tài khoản |
| ui/Button | AppButton, FilledButton/OutlinedButton cấu hình riêng | primary/secondary/danger, loading/disabled/pressed |
| ui/Input, Form, SearchInput | AppTextField, Form, TextFormField, DropdownButtonFormField | focus/error/disabled, validation và keyboard |
| ui/Card, StatCard, MetaGrid | AppCard, StatCard, Wrap/GridView | border, spacing, label/value |
| ui/Badge, StatusBadge; project/ProjectStateBadge | AppStatusBadge, enum + label/tone mapping | nhãn chữ đi cùng màu |
| ui/SegmentedTabs, PhaseTwoTabs | TabBar/SegmentedButton được style | giữ selected state, padding, cuộn khi hẹp |
| ui/PageHeading, SectionHeader, BackLink, Avatar | widget tương ứng + Text / CircleAvatar / back action | typography thực tế và context |
| ui/Modal, ConfirmModal, MoreMenu | bottom sheet/Dialog/PopupMenuButton | xác nhận/hủy, bàn phím, đóng và focus |
| ui/Toast, Notice | ScaffoldMessenger + AppNotice | success/error, nội dung không chỉ biểu thị bằng màu |
| ui/EmptyState; review/ReviewListSkeleton | EmptyState / ReviewListSkeleton | loading/content/empty/error cho danh sách |
| ui/ProgressBar, QRCode | LinearProgressIndicator / QR widget sau khi chọn package | không tự thêm dependency lúc khởi tạo |
| filters/SmartFilterBar, OptionList, Popover, TimeControls | filter chips + bottom sheet + date controls | apply/clear/cancel, giữ filter theo context |
| project/ClassCard, ProjectCard, MemberRow | widget nghiệp vụ tương ứng | status, thành viên, tiến độ, action |
| project/*FormModal, AddStudentsModal; lab/LabStructureEditor | form sheet + LabStructureEditor | giới hạn nhóm/lớp và validate dependency |
| document/DocumentCard, DocumentRoadmapItem | DocumentCard / roadmap list | version, deadline, điều kiện nộp |
| document/DocumentViewer, OriginalDocumentPanel, SampleDocumentPreview | DocumentInfoPanel / sample preview native | DocumentViewer chỉ có metadata; sample minh họa không phải file thật; viewer PDF native là hạng mục đánh giá riêng |
| review/ReviewRequestCard, ReviewContextCard, StatusTracks | widget review tương ứng | tách trạng thái tài liệu / AI / Supervisor |
| review/AIReviewSection, ReviewAIStatus, AIFindingCard | AIReviewSection + state view + finding card | loading/completed/error, phân biệt gợi ý AI |
| review/FeedbackComposer, FeedbackItem, DecisionModals | Form + feedback list + confirmation sheet | severity/category/pageRef, lý do, chọn phản hồi chính thức |
| review/VersionCard, TimelineItem | version card + timeline | version bất biến, thời gian, tác giả |

Bottom nav trong code nhóm `/classes`, `/groups`, `/semesters`, `/documents`, `/rule-sets`, `/courses` vào Dự án; `/review-history` vào Đánh giá. `/course-offerings` và `/project-registrations` chưa có trong mảng `extra`: ghi nhận để đối chiếu, không âm thầm đổi hành vi.

## 4. Routes Supervisor → screens

Source: `src/app/router.tsx`. File React nằm trong `src/pages/`; mỗi Flutter screen dự kiến dùng hậu tố `Screen` thay `Page`, với cùng tên gốc và cùng tham số ID.

| Route | React Page | Flutter Screen / feature |
|---|---|---|
| /login | auth/LoginPage | LoginScreen / auth (dùng chung role) |
| /dashboard | dashboard/DashboardPage | DashboardScreen / dashboard |
| /project-registrations | projects/ProjectRegistrationsPage | ProjectRegistrationsScreen / projects |
| /classes | classes/ClassListPage | ClassListScreen / classes |
| /classes/:classId | classes/ClassDetailPage | ClassDetailScreen(classId) |
| /projects | projects/ProjectListPage | ProjectListScreen / projects |
| /projects/:projectId | projects/ProjectDetailPage | ProjectDetailScreen(projectId) |
| /projects/:projectId/documents | documents/ProjectDocumentsPage | ProjectDocumentsScreen(projectId) / documents |
| /reviews | reviews/ReviewRequestsPage | ReviewRequestsScreen / reviews |
| /reviews/:reviewId | reviews/ReviewWorkspacePage | ReviewWorkspaceScreen(reviewId) |
| /reviews/:reviewId/ai-result | reviews/AIReviewResultPage | AIReviewResultScreen(reviewId) |
| /reviews/:reviewId/versions | reviews/VersionHistoryPage | VersionHistoryScreen(reviewId) |
| /reviews/:reviewId/history | reviews/ReviewHistoryPage | ReviewHistoryScreen(reviewId) |
| /review-history | reviews/ReviewHistoryIndexPage | ReviewHistoryIndexScreen |
| /documents | documents/DocumentListPage | DocumentListScreen / documents |
| /groups | groups/GroupListPage | GroupListScreen / groups |
| /groups/:groupId | groups/GroupDetailPage | GroupDetailScreen(groupId) |
| /semesters | semesters/SemesterListPage | SemesterListScreen / academic |
| /rule-sets | semesters/RuleSetListPage | RuleSetListScreen / academic |
| /courses | semesters/CourseListPage | CourseListScreen / academic |
| /courses/:courseId | semesters/CourseDetailPage | CourseDetailScreen(courseId) |
| /course-offerings/:offeringId | semesters/CourseOfferingDetailPage | CourseOfferingDetailScreen(offeringId) |
| /students | students/StudentListPage | StudentListScreen / students |
| /notifications | notifications/NotificationsPage | NotificationsScreen / notifications |
| /profile | profile/ProfilePage | ProfileScreen / profile |

`/` và wildcard Supervisor redirect về `/dashboard`. Auth guard trong MobileAppLayout đưa phiên chưa đăng nhập về `/login`, role Student về `/student/dashboard`. Các routes `/student/*` là nhánh riêng ngoài đợt Supervisor đầu; không nhập chúng vào shell Supervisor.

Workspace có 4 panel `document/ai/feedback/history`, route handle `wide: true`; Flutter cần giữ panel và context review/version, dùng layout đáp ứng thay vì ép bố cục desktop vào mobile.

## 5. State và dữ liệu cần chuyển

- `src/types/index.ts` → Dart immutable models/enums. Giữ chính xác tên trạng thái `notAccepted`, `inReview`, `notRun` từ code, không thay bằng `rejected`/`reviewing` trong tài liệu cũ.
- `src/data/{managementStore,reviewStore,notificationStore}.ts`, selectors và mockData → repository interfaces + mock implementations. React localStorage là dữ liệu demo, không phải backend.
- `src/app/auth.ts` → mock session repository + session ViewModel; role selection hiện tại không phải xác thực thật.
- `src/lib/{config,courseRules,rubric,academic,studentPrecheck,smartFilter,time}.ts` → domain rules/selectors. Giữ Course khác CourseOffering; Class override không sửa cấu trúc Offering; phụ thuộc LabItem và deadline theo context.
- `reviewStore.runEvaluation` mô phỏng chờ 1200ms, chụp rule/version snapshot rồi trả mock result. Tách AI evaluation khỏi quyết định Supervisor; AI không tự approve.
- DecisionModals: approve → approved, revise → needsRevision, reject → notAccepted; validate lý do/phản hồi, chặn khi domain rules không cho phép, ghi audit/notification nhất quán.

## 6. Điều kiện nghiệm thu khi triển khai

Đối chiếu screenshot cùng seed/context ở 360×800 và 412×892, thêm 390dp và text scaling; giữ palette, copy, icon, spacing, active tab. Kiểm tra safe area, keyboard, back, scroll, sticky action không che nội dung. Component hiện tại áp dụng vùng chạm 48dp; tài liệu cũ ghi tối thiểu 44dp. Mỗi danh sách có loading/data/empty/error, ID không tồn tại và phục hồi lỗi. Test nghiệp vụ cho version snapshot, dependency, feedback/decision và role guard. Không dùng WebView để bọc React.
