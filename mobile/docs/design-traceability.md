# Design traceability — Lab 2 → Lab 3 phases 1–2

Ngày cập nhật: 25/10/2026. Nguồn React `D:/UI AI Review` chỉ đọc. Baseline là source hiện tại cộng với các khác biệt handoff đã ghi trong [mapping](react-flutter-mapping.md); chưa xác minh trực tiếp Figma hoặc visual parity của screen chưa chuyển đổi. Các ghi nhận phase 1 bên dưới là lịch sử; phạm vi route đã mở rộng ở phase 2.

## Tokens đã triển khai

| Nguồn React/Lab 2 | Flutter hiện có | Giá trị/quy tắc |
|---|---|---|
| src/index.css @theme | lib/theme/app_colors.dart | toàn bộ 17 token màu, gồm brand-hover; thêm white từ surfaces/text của component |
| src/index.css body | lib/theme/app_typography.dart | Inter, body 14/400, line-height 1.45 |
| src/components/ui/PageHeading.tsx | AppTypography.pageHeading | 26/600, line-height 1.18 |
| src/styles/content-cleanup.css | AppTypography.effectiveSmall | 14px cho các chữ 10–13px trong mobile-app; giữ weight theo vai trò khi chuyển screen |
| design-system.md typography | lab2PageTitle/sectionTitle/blockTitle/lab2BodySmall/lab2Label/lab2Micro | giữ thang 22/20/16/14/13/12/11, không dùng để ghi đè CSS effective |
| design-system.md spacing | lib/theme/app_spacing.dart | 4/8/12/16/24/32/48 |
| src/layouts/MobileAppLayout.tsx | pagePadding/pageTop | 20/12, gap 16 |
| Button.tsx và content-cleanup.css | tapMin | 48dp (handoff cũ tối thiểu 44) |
| design-system.md radius | lib/theme/app_radius.dart | chip 6, button 8, card 12, dialog 16, pill 999 |
| Modal.tsx | AppRadius.modal | 12, giữ riêng với dialog 16 trong handoff |
| src/index.css mobile-header-inner | headerHeight | 56dp mobile; desktop 64 dành cho lần chuyển layout |
| @theme + Card.tsx | lib/theme/app_theme.dart | màu gán tường minh, card không elevation, không tự tint màu surface |
| design-system.md elevation | lib/theme/app_shadows.dart | offset/blur/alpha: 0,1/2/.06; 0,2/8/.08; 0,8/24/.12; chỉ dùng khi source có shadow |
| Google Fonts Inter dùng bởi React | assets/fonts/Inter-Variable.ttf + OFL.txt, pubspec.yaml | font nhúng offline từ Google Fonts, variable weights; bản font không được chứng minh byte-identical với Google CSS thời điểm Lab 2 |

Nguồn font: https://github.com/google/fonts/tree/main/ofl/inter (SIL OFL). Shared widgets và Dashboard đã được dựng theo source; mức độ khớp và sai khác được ghi bằng ảnh/số đo ở báo cáo phase 1. Component chưa chuyển không được coi là đã đạt UI Lab 2 chỉ vì có ThemeData.

## Components và trạng thái chuyển đổi

| Nhóm nguồn | Đích dự kiến | Trạng thái |
|---|---|---|
| layout/MobileHeader | widgets/MobileHeader | Đã chuyển header căn trái, Files Lucide 24, chữ 17/600, toolbar 56 + viền 1 |
| layout/BottomNavigation | widgets/AppBottomNavigation | Đã chuyển 5 tab, active state, cùng icon và route grouping; có SafeArea Android |
| layout/MobileAppLayout | screens/dashboard/DashboardScreen | Đã chuyển shell mobile; chưa chuyển sidebar desktop/auth guard |
| ui/Button | widgets/AppButton + AppTheme | Đã chuyển primary/secondary/danger, loading/disabled, min 48, radius 8 |
| ui/Badge | widgets/AppBadge | Đã chuyển 6 tone, chữ + cặp màu, radius 5 theo CSS thực tế |
| ui/Card, StatCard | widgets/AppCard, StatCard | Đã chuyển card phẳng viền 1/radius 12; grid cao theo nội dung |
| ui/EmptyState | widgets/AppEmptyState | Đã chuyển nhãn/icon/action và viền đứt nét |
| Quy ước loading/error/retry | widgets/AppLoadingState, AppErrorState | Đã bổ sung cho dữ liệu bất đồng bộ; source Dashboard không có cùng loading screen |
| ui/Input, Form, StatusBadge, Modal, ConfirmModal, Toast, Notice | widgets ở các phase sau | Chưa chuyển; ThemeData mới chuẩn bị input/button/card styles |
| filters/*, ui/SegmentedTabs, PhaseTwoTabs | filter sheet/chips, tabs | Chưa chuyển |
| project/*, lab/LabStructureEditor | cards/forms/lab editor | Chưa chuyển |
| document/* | native metadata/sample preview/document UI | Chưa chuyển; không WebView |
| review/* | review cards, status tracks, AI states, feedback/decision/history | Chưa chuyển |
| pages/dashboard/DashboardPage | screens/dashboard/DashboardScreen + widgets riêng của feature | Đã chuyển phần yêu cầu phase 1 và các mục thu gọn phụ; đã kiểm thử/chụp/đối chiếu Pixel 4a ở 360/390/412dp |
| Flutter counter demo | screens/DemoScreen + widgets/DemoCounterValue | Giữ để kiểm thử foundation, không còn là home |

## Route inventory

Bảng dưới lấy từ mapping đã đối chiếu `src/app/router.tsx`. Home hiện là DashboardScreen. Chỉ Dashboard được chuyển trong phase này. CTA/bottom nav đi đến một NavigationDestinationScreen dùng chung để kiểm tra route và Back; các route khác chưa phải màn nghiệp vụ đã chuyển.

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

Nhánh `/student/*` ngoài đợt Supervisor đầu. Auth/role guards, wildcard redirect và active-tab mapping giữ theo inventory gốc khi triển khai. Mã S01–S14 khác nhau giữa hai handoff: route/component là khóa traceability.

## Cổng đối chiếu khi chuyển từng screen

1. Ghi source route/components/CSS effective, seed data và state cần tái hiện.
2. So sánh ở 360×800 và 412×892, bổ sung 390dp/text scale; kiểm tra Inter, màu, khoảng cách, radius, label/icon và thứ tự thao tác.
3. Loading/data/empty/error; disabled/pressed/focus; back, safe area, keyboard và sticky actions.
4. Giữ document/AI/Supervisor status riêng; quyết định do Supervisor xác nhận, không do AI tự approve.
5. Ghi rõ khác biệt baseline và lý do, không đổi UI để làm test pass.

## Ghi nhận phase 1 — 25/10/2026

- Đã đọc TSX và CSS effective của Dashboard và các component dùng chung. Project active giữ nhãn **Đang thực hiện** theo projectStatuses.ts.
- Đã chụp React: [360×800](evidence/phase1/react-360.png), [390×844](evidence/phase1/react-390.png), [412×892](evidence/phase1/react-412.png). JSON cùng tên ghi bounding boxes. Source được sao chép vào `.local/react-reference`; cache Vite nằm trong dự án Flutter, không ghi vào source gốc.
- Fixture từ initial stores thật, không dùng dữ liệu người dùng đã lưu. Thống kê baseline: 3/6/8/3/0/10; ba request đầu review-001/review-008/review-005.
- Giữ Inter offline và hình học Lucide v1.55.0 của dependency React, có ISC LICENSE. Grid dùng chiều cao nội dung từng hàng; text tracking đặt 0 như CSS, badge radius 5 thay vì chip radius 6 của handoff cũ.
- Đã sửa bộ chọn học kỳ căn phải và padding ngang mỗi tab về 1px như source. Caption navigation giữ style Inter 14px, chỉ scaleDown nhẹ khi advance width native vượt tab để tránh mất chữ; mũi tên dropdown dùng chevron thay tam giác Material.
- Dữ liệu đi qua AsyncNotifier → DashboardRepository → FakeDashboardService. Chọn học kỳ, kiểm tra ID và thống kê ở ViewModel; chưa có Firebase/xác thực thật.
- Các route ngoài Dashboard chỉ có điểm dừng thông báo “Chức năng đang được chuẩn bị.”; không tính là đã chuyển màn Đánh giá/Workspace.
- SmartFilterBar nâng cao trong mục “Tìm kiếm & phạm vi” (course/class facets, saved views) và sidebar desktop chưa chuyển; bộ chọn học kỳ chính đã hoạt động.
- Dropdown native Flutter, hiệu ứng nhấn, rasterization và system insets có thể khác HTML/CSS. Kết quả ảnh Android và sai lệch sau đối chiếu được cập nhật ở [báo cáo phase 1](phase1-ui-report.md).
- Kiểm chứng cuối: analyze sạch, 12 test đạt; cả 3 lượt integration Android đạt. Đã xem ảnh ghép [360](evidence/phase1/comparison-360.png), [390](evidence/phase1/comparison-390.png), [412](evidence/phase1/comparison-412.png); lệch Y CTA khoảng 1.14–1.73dp do line-height. Emulator đã được khôi phục về cấu hình gốc và chạy entrypoint Dashboard bình thường.

Chi tiết mapping và domain rules: [react-flutter-mapping.md](react-flutter-mapping.md).

## Phase 2 — cập nhật 25/10/2026

Phạm vi Rule Set đã được người dùng xác nhận: giữ thư viện dùng chung và phạm vi gán theo Course như React; không chuyển sang ownership độc quyền.

| Route / source thực tế | Flutter | Trạng thái và tương tác |
|---|---|---|
| `/courses` · semesters/CourseListPage.tsx | academic/CourseListScreen | Data/empty/loading/error-retry; thêm môn, mở đợt, disclosure, điều hướng |
| `/courses/:courseId` · CourseDetailPage.tsx + RuleSetListPage.tsx | CourseDetailScreen + RuleSetPanel | Hai nhóm cấu hình, thư viện/phạm vi môn, editor/xem/nhân bản/gán rule, các đợt học; có not-found |
| `/course-offerings/:offeringId` · CourseOfferingDetailPage.tsx | OfferingDetailScreen | Cấu hình lưu bằng nút; Lab lưu ngay; danh sách/tạo lớp; mỗi tab có empty phù hợp, route có loading/error-retry/not-found |
| `/classes` · classes/ClassListPage.tsx | ClassListScreen | Tìm/lọc/chip/saved view trong phiên; tạo/sửa/lưu trữ/khôi phục/xóa trống; data/empty/loading/error-retry |
| `/classes/:classId` · ClassDetailPage.tsx | ClassDetailScreen | Tổng quan/Nhóm/Sinh viên/Dự án/Yêu cầu đánh giá; thêm nhóm, sinh viên qua QR/CSV/danh bạ; data/empty/loading/error-retry/not-found |
| `/rule-sets` · RuleSetListPage.tsx không courseId | RuleSetSelectionScreen | Chọn môn để cấu hình, data/empty/loading/error-retry |

| Component React | Flutter dùng lại/mới | Ghi nhận |
|---|---|---|
| PageHeading, BackLink, PhaseTwoTabs, SegmentedTabs | AppPageHeading, AcademicBackLink, AppTabs | Cùng nhãn, thứ tự, tab mặc định; Back pop stack và fallback route |
| Modal, Notice, MoreMenu | showAppSheet/AppSheetLayout, AppNotice, AppMoreMenu | Native bottom sheet cuộn, footer tránh bàn phím; lỗi lưu giữ draft |
| Form/ChoiceChips, RuleEditor | AcademicFieldView + AcademicFormViewModel | Input 16, border-muted, radius 8; schema dùng chung; validation/ghi ở ViewModel |
| SmartFilterBar | ClassFilterBar + ClassFilterViewModel, AppSelectButton/AppFilterChip | Học kỳ/môn/trạng thái/lịch/buổi; chip cuộn ngang; chế độ xem trong bộ nhớ |
| ClassCard | AcademicClassCard | Dùng chung ở danh mục và tab Lớp của đợt |
| LabStructureEditor | LabEditor + form Lab/item + AcademicViewModel | Thêm/sửa/di chuyển/xóa, gỡ dependency, clone ID/remap, template |
| ProjectCard/MetaGrid/ProgressBar trong ClassDetail | GroupSummaryCard, AppMetaGrid, AcademicProgress | Tóm tắt nhóm/dự án; giới hạn thành viên theo Class, hoạt động theo nhãn React |
| AddStudentsModal/QRCode | StudentEnrollmentSheet + StudentEnrollmentViewModel + StudentDeviceGateway | QR/copy/regenerate, CSV preview/validation/batch, chọn danh bạ; XLSX chỉ mẫu như React |
| Rule assignment và rule view | AcademicFormSheet(kind assignment), RuleDetails | Đợt → lớp → mục phụ thuộc nhau, chỉ rule active; chi tiết criteria/cờ AI/ngưỡng |

Các shared Phase 1 tiếp tục được dùng. Tokens bổ sung vẫn ở `lib/theme/`: chữ input/course code/course name/rule heading; QR, modal max height, progress track và avatar. Không tạo theme/kiến trúc thứ hai. Logic domain: [báo cáo Phase 2](phase2-ui-report.md), [kiến trúc](architecture.md).

Select của đợt học và Class dùng style 14 tương ứng utility text-13 được content-cleanup nâng lên 14; input dùng Form chung và select Rule Editor giữ 16. Không đồng nhất mọi input/select thành cùng một cỡ khi CSS effective khác nhau. Navigation trang đợt học không chọn tab mặc định vì source BottomNavigation không nhóm route `/course-offerings` vào tab nào.

### Phạm vi và khác biệt được giữ rõ

- Sáu route trên đã có UI và thao tác thực với fake repository; không đánh dấu chỉ dựa vào router. GroupDetail/ProjectDetail/ReviewDetail chưa chuyển, liên kết vẫn tới điểm dừng có thông báo.
- Rule Set dùng chung; Course chỉ xác định tập rule qua assignment. Priority item → Class → offering; Class item override cách ly và lịch sử review không bị sửa. Null và Lab override rỗng được phân biệt.
- Hạ giới hạn nhóm không xóa người. Khóa đổi offering khi lớp đã có nhóm. Các kiểm tra trùng mã/sĩ số/lưu trữ/lịch sử chặt hơn UI mock nguồn; lưu trữ là chỉ đọc đúng Notice nguồn.
- CSV đọc thật theo parser đơn giản của Lab 2, tối đa 500 dòng. XLSX chỉ dữ liệu mẫu và có nhãn giải thích; chưa coi là nhập XLSX production hoặc dịch vụ QR tự tham gia thật.
- Saved view của Class chỉ tồn tại trong phiên fake, khác localStorage React. Android dùng lịch/popup/chọn tệp/bàn phím native. Inter rasterization, line wrapping và system safe area có khác biệt; không khẳng định pixel-identical hay xác nhận Figma.
- Ảnh đối chiếu, số đo và kết quả kiểm tra cuối: `docs/evidence/phase2/`, [báo cáo Phase 2](phase2-ui-report.md). Không sử dụng fixture làm dữ liệu Lab 3 cuối cùng.

### Kiểm chứng cuối Phase 2

Analyze sạch; **70 test đạt**; **3/3 lượt Android đạt** trên Pixel_4a_API_34 tại 360/390/412dp. Có **51 ảnh native, 42 ảnh React và 42 cặp đối chiếu**, gồm cả năm tab ClassDetail, form Course, Lab, lớp thuộc đợt và editor/assignment Rule Set. [Danh mục ảnh](evidence/phase2/README.md).

Đã đối chiếu và sửa modal/footer/Notice, các hàng Lab, ngày theo định dạng React, gap tab, bảng nhóm, badge trạng thái và active navigation của `/course-offerings`. `ClassOverview` tách thành widget riêng, tiếp tục dùng StatCard/Card/Badge/Progress. Bộ đếm yêu cầu mở loại `approved`, `needsRevision`, `notAccepted` theo `selectors.isCompleted`, giữ nguyên reviewState; SE1701 có 6 yêu cầu mở.

18 phép đo PageHeading: lệch Y tối đa 0dp; lệch chiều cao tối đa 0,36dp. Còn khác nhỏ về font/glyph/ngắt dòng, kích thước điều khiển native và vài khoảng cách; không đánh dấu pixel-identical. GroupDetail/ProjectDetail/ReviewDetail vẫn ngoài phạm vi. Dữ liệu fake và saved views không được coi là dữ liệu Lab 3 chính thức.
