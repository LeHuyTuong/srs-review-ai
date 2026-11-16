# Phase 3 — Phạm vi và nguồn đối chiếu

Ngày 25/10/2026. Nguồn chính thức: `D:/UI AI Review`, chỉ đọc. Nối tiếp ứng dụng **Supervisor** đã chuyển ở Phase 1–2. Không thêm nhánh đăng nhập hoặc ứng dụng Student vào kiến trúc foundation hiện có.

## Route và tương tác từ React

| Route Supervisor | Source React `src/` | Tương tác |
|---|---|---|
| `/groups` | pages/groups/GroupListPage.tsx | Nhóm theo lớp active; thêm nhóm; compact ProjectCard; nhóm rỗng |
| `/groups/:id` | pages/groups/GroupDetailPage.tsx | Đổi tên, thêm/bỏ thành viên, trưởng nhóm đầu danh sách, gán/tạo dự án, xóa nhóm rỗng chưa có lịch sử |
| `/projects` | pages/projects/ProjectListPage.tsx | Tạo; tìm kiếm; phạm vi học kỳ/môn/lớp/nhóm/trạng thái/lịch/buổi; saved view |
| `/projects/:id` | pages/projects/ProjectDetailPage.tsx | Tổng quan, tài liệu, thành viên, lịch sử, thông tin; sửa; lưu trữ/khôi phục; xóa khi chưa có lịch sử |
| `/projects/:id/documents` | pages/documents/ProjectDocumentsPage.tsx | Tất cả/chờ đánh giá/cần sửa/khóa; ưu tiên inReview rồi waiting |
| `/project-registrations` | pages/projects/ProjectRegistrationsPage.tsx | Nhận xét nội tuyến; duyệt/yêu cầu sửa/từ chối; xem lịch sử; duyệt tạo dự án |
| `/documents` | pages/documents/DocumentListPage.tsx | Chỉ mục tài liệu đã nộp/nháp, filter và liên kết |
| `/reviews` | pages/reviews/ReviewRequestsPage.tsx | Mặc định waiting trong học kỳ; xem tất cả/việc cần làm; filter đa chiều, saved view và năm thứ tự sắp xếp |
| `/reviews/:id` | pages/reviews/ReviewWorkspacePage.tsx | Tài liệu/AI/phản hồi/lịch sử; thông tin bản nộp; bắt đầu; quyết định; chọn phản hồi công bố |
| `/reviews/:id/ai-result` | pages/reviews/AIReviewResultPage.tsx | Chạy/chạy lại/retry AI; bảng tiêu chí; mở tất cả; cần chú ý/tất cả; lịch sử AI chỉ đọc |
| `/reviews/:id/versions` | pages/reviews/VersionHistoryPage.tsx | Danh sách bất biến; xem bản; so sánh metadata hai phiên bản |
| `/reviews/:id/history` | pages/reviews/ReviewHistoryPage.tsx | Timeline và đúng ID phản hồi được công bố trong từng quyết định |
| `/review-history` | pages/reviews/ReviewHistoryIndexPage.tsx | Chỉ mục nhật ký, filter theo sự kiện mới nhất, ba sự kiện cuối mỗi tài liệu |

## Logic đã đọc

- Routing: `src/app/router.tsx`.
- `src/data/managementStore.ts`, `reviewStore.ts`, `selectors.ts`, `filterRecords.ts`, `selfService.ts`, `selfServicePolicy.ts`, `projectStatuses.ts`.
- `src/types/index.ts`, `lib/config.ts`, `academic.ts`, `rubric.ts`, `reviewPresentation.ts`, `smartFilter.ts`, `time.ts`, `uiLabels.ts`.
- `data/mockData.ts`, `demoSeed.ts`, `selfServiceSeed.ts`, `documentSamples.ts` và hai store khởi tạo.
- Component Group/Project form, ProjectCard, MemberRow; ReviewRequestCard, StatusTracks, ReviewAIStatus, AIReviewSection, FeedbackComposer, FeedbackItem, DecisionModals, VersionCard, ReviewContextCard, TimelineItem.
- DocumentCard, DocumentRoadmapItem, SampleDocumentPreview, DocumentViewer, useDocumentState. `OriginalDocumentPanel` được kiểm tra bằng tìm kiếm tham chiếu: component tồn tại nhưng **không được route Supervisor hiện tại sử dụng**; không thêm một workflow chọn/tải tệp mới vào Flutter.
- `styles/phase-two.css`, `review-refinement.css`, `content-cleanup.css` và các tokens nền đã truy vết ở Phase 2.

## Biên dữ liệu và các ngoại lệ

- Rule Set dùng chung, gán theo Course qua offering/class/item như lựa chọn đã xác nhận. Snapshot bản nộp ưu tiên hơn cấu hình hiện hành.
- `needsRevision` là lượt giảng viên đã hoàn tất, vẫn có thể chờ sinh viên nộp phiên bản mới. Không gộp với waiting/inReview.
- AI chỉ là `mockEvaluation` theo kịch bản `documentSamples`; không đọc byte tài liệu và không phê duyệt thay giảng viên. Oracle 63 tổ hợp được sinh từ chính hàm React, độc lập với Dart.
- Supervisor chỉ xem tài liệu/phiên bản. Các route `/student/*` có upload/submit riêng theo vai trò; không hiển thị nút upload cho Supervisor.
- Giữ nháp khi lỗi ghi; kiểm tra revision khi commit; dữ liệu fake chỉ sống trong phiên ứng dụng.
- Lớp/dự án lưu trữ khóa ghi. Nhóm vượt giới hạn giữ thành viên cũ và chặn thêm mới.
- Sửa một lỗi tham chiếu ở nhánh xóa nhóm rỗng có dự án chưa có lịch sử: Flutter giữ `classId` suy ra của dự án khi bỏ `groupId`, để dự án còn thuộc lớp và có thể gán lại; React xóa nhóm đơn lẻ có thể để lại liên kết nhóm không tồn tại. Không xóa dự án/tài liệu kèm theo.

## Cách kiểm chứng

Chỉ bắt đầu analyze/test/native/đối chiếu sau khi hoàn thiện triển khai các route. Bộ test toàn dự án bao gồm regression Phase 1–2; driver Android kiểm tra các route baseline, các tab/form và mutation liên thông trước/sau. Ảnh baseline chụp trước mutation. Reference React chạy từ bản sao trong `.local`, context trình duyệt độc lập, không dùng storage người dùng.

Kết quả và giới hạn sau kiểm chứng được ghi trong `phase3-ui-report.md`, `design-traceability.md` và `evidence/phase3/`.
