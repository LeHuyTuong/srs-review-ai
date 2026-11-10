# Business Rules — srs-review-ai (slide 08 / 10 / 13)

Nguồn sự thật: code ở working tree ngày 2026-11-10. Mã `BR-<WF>-<nn>` **do tài liệu này đặt**, code không mang mã này — cột "Vị trí" là bằng chứng. Thông điệp chép nguyên văn từ code.

- WF-01 = Mở dự án SRS cho nhóm sinh viên
- WF-02 = Nộp SRS và duyệt có AI hỗ trợ
- WF-03 = Theo dõi kết quả duyệt tài liệu

Đường dẫn mobile viết tắt: `fe/` = `mobile/lib/features/academic/presentation/viewmodels/`, `dom/` = `mobile/lib/core/domain/academic/`, `stu/` = `mobile/lib/features/student/`.

## WF-01 — Mở dự án

| Mã | Phát biểu nghiệp vụ | Vị trí | Thông điệp | Case E2E |
|---|---|---|---|---|
| BR-01-01 | Dự án chỉ mở cho nhóm thuộc đợt học đang hoạt động | `fe/management_form_view_model.dart:456`, `fe/management_actions.dart:145` | "Chọn nhóm thuộc đợt học đang hoạt động." / "Đợt học không còn hoạt động." | FL01 |
| BR-01-02 | Mỗi nhóm có tối đa một dự án | `fe/management_form_view_model.dart:469`, `fe/management_actions.dart:156` | "Nhóm đã có dự án." | — |
| BR-01-03 | Tên bắt buộc; hạn nộp không trước ngày bắt đầu | `fe/management_form_view_model.dart:461`, `fe/management_actions.dart:166` | "Hạn nộp không được trước ngày bắt đầu." / "Nhập tên và khoảng thời gian dự án hợp lệ." | FL02 |
| BR-01-04 | Dự án đã lưu trữ chỉ được xem | `fe/management_actions.dart:138` | "Dự án đã lưu trữ, chỉ được xem." | — |
| BR-01-05 | Nhóm không vượt giới hạn thành viên của lớp | `dom/academic_policy.dart:157`, `fe/management_form_view_model.dart:432` | "Nhóm đã đạt giới hạn thành viên của lớp." | — |
| BR-01-06 | Bộ quy tắc chỉ kích hoạt khi có ≥1 tiêu chí bật và checklist đủ | `dom/academic_policy.dart:52` | "Cần ít nhất một tiêu chí bật và checklist đầy đủ trước khi kích hoạt." | — |
| BR-01-08 | Duyệt đăng ký dự án: chỉ yêu cầu `pending`; quyết định khác Duyệt cần lý do | `fe/management_actions.dart:274-287` (`decideRegistration`) | "Yêu cầu không còn chờ duyệt." / "Nhập lý do hoặc nội dung cần sửa." | — |
| BR-01-07 | Không bắt buộc AI khi AI tắt, hoặc khi không tiêu chí nào bật AI | `dom/academic_policy.dart:26`, `:58` | "Không thể bắt buộc AI khi AI bị tắt." / "Cần ít nhất một tiêu chí bật AI để bắt buộc Đánh giá AI." | — |

## WF-02 — Nộp SRS và duyệt có AI

| Mã | Phát biểu nghiệp vụ | Vị trí | Thông điệp | Case E2E |
|---|---|---|---|---|
| BR-02-01 | Phải đăng nhập mới nộp được | `stu/presentation/viewmodels/student_upload_view_model.dart:118` | "Vui lòng đăng nhập lại để nộp bài." | FL11 |
| BR-02-02 | Phải chọn tệp trước khi nộp | `student_upload_view_model.dart:122` | "Vui lòng chọn tệp SRS trước." | FL11 |
| BR-02-03 | Chỉ nhận định dạng cho phép | `stu/data/services/student_file_picker_service.dart:55` | "Chỉ hỗ trợ tệp …" | — |
| BR-02-04 | Tệp không được rỗng | `student_file_picker_service.dart:61` | "Tệp rỗng hoặc không thể đọc." | — |
| BR-02-05 | Dung lượng ≤ `max_upload_file_size_mb` (Remote Config, 1–100) | `student_file_picker_service.dart:67`, `server/app/api/remote_config.py:29` | "Tệp có dung lượng X MB, vượt giới hạn Y MB." | TC10 |
| BR-02-06 | Phải có bộ quy tắc "Đang áp dụng" trước khi đánh giá | `dom/management_queries.dart:147` | "Cần gán một bộ quy tắc Đang áp dụng trước khi đánh giá." | — |
| BR-02-07 | Nếu bộ quy tắc bắt buộc AI: AI phải xong trước khi giảng viên đánh giá | `dom/management_queries.dart:151` | "Bộ quy tắc yêu cầu hoàn tất Đánh giá AI trước khi giảng viên bắt đầu đánh giá…" | FL04 |
| BR-02-08 | Không ra quyết định khi AI đang chạy | `fe/review_actions.dart:293`, `dom/review_policy.dart:276` | "AI đang xử lý." | FL04 |
| BR-02-09 | Quyết định "Yêu cầu sửa" cần lý do | `fe/review_actions.dart:207` | "Cần lý do/phản hồi cho quyết định này." | FL05 |
| BR-02-10 | Phản hồi không được trống | `fe/review_actions.dart:114`, `:179`, `fe/management_form_view_model.dart:442` | "Nhập nội dung phản hồi." | FL05 |
| BR-02-11 | Dự án chỉ đọc/lưu trữ không duyệt được | `fe/review_actions.dart:52`, `:174` | "Dự án chỉ đọc." | — |
| BR-02-12 | ~~Chỉ quyết định yêu cầu còn chờ duyệt~~ — **bỏ**: dòng cũ thuộc duyệt *đăng ký dự án*, đã chuyển thành BR-01-08. Duyệt SRS không kiểm trạng thái nguồn (xem "Chưa cài") | chưa có | — | — |
| BR-02-13 | Lỗi AI chỉ giữ khi trích dẫn khớp văn bản gốc ≥ 0.92; số bị loại trả về `dropped_issue_count` | `server/app/config/settings.py:110`, `server/app/application/review_service.py:162-174` | (không có thông điệp — lỗi bị loại im lặng, chỉ đếm) | FL04 |
| BR-02-14 | Mỗi người tối đa 50 lượt chấm AI/ngày; vượt → HTTP 429 | `settings.py:108`, `server/app/api/review.py:74-79` | "Daily review limit reached (50). Retry after Ns." | — |
| BR-02-15 | Lượt chấm AI quá 90 giây thì app báo lỗi, cho thử lại | `mobile/lib/core/services/ai_review_service.dart:132` | (AiReviewException) | FL06 |
| BR-02-16 | Quyết định chỉ là Duyệt / Yêu cầu sửa / Không chấp nhận; trừ Duyệt, mọi quyết định cần lý do | `fe/review_actions.dart:203-207` | "Quyết định không hợp lệ." / "Cần lý do/phản hồi cho quyết định này." | FL04, FL05 |
| BR-02-18 | Bài đã có quyết định (`approved`/`needsRevision`/`notAccepted`) là trạng thái cuối, không sửa/quyết định lại | `dom/management_queries.dart:18-22`, `fe/review_actions.dart:44-47` | "Đánh giá đã hoàn tất; lịch sử được giữ nguyên." | FL14 (chưa chạy) · unit `mobile/test/business_rules_coverage_test.dart` |
| BR-02-17 | Chỉ yêu cầu đang `waiting` mới chuyển sang `inReview` khi GV mở | `fe/review_actions.dart:88-97` | (không thông điệp — bỏ qua im lặng) | FL04 |

Trạng thái thật của bài nộp (`supervisorStatus`): `waiting` → `inReview` (`fe/review_actions.dart:97`) → `approved` | `needsRevision` | `notAccepted` (`fe/review_actions.dart:203`). Model `docs/uml/state/decision-status.model.json` mới có 2 state (Changes Requested, Approved) — thiếu `waiting`, `inReview`, `notAccepted`.

## WF-03 — Theo dõi kết quả

| Mã | Phát biểu nghiệp vụ | Vị trí | Thông điệp | Case E2E |
|---|---|---|---|---|
| BR-03-01 | Phiên hết hạn → buộc đăng nhập lại | `mobile/lib/core/domain/session_scope.dart:14` | "Phiên đã kết thúc. Vui lòng đăng nhập lại." | FL10 |
| BR-03-02 | Dự án chỉ "xong" khi mọi tài liệu `approved` | `dom/management_queries.dart:138` | (không thông điệp — ảnh hưởng thống kê) | FL04, FL07 |

## Chưa cài (nói thẳng khi bảo vệ)

- Không có mã BR nào trong code; bảng này là ánh xạ đặt sau.
- BR-02-13 loại lỗi AI **không báo người dùng** — chỉ có số `dropped_issue_count`.
- Không có luật hạn nộp cứng: nộp sau `deadline` không bị chặn (chưa tìm thấy check).
- Chuyển trạng thái bị cấm **có cài** (BR-02-18) và **đã có test** (2026-11-10): unit `mobile/test/business_rules_coverage_test.dart` (xanh) + case E2E FL14 `e2e_test/flows.py:464` (viết xong, **chưa chạy**).
- `decideReview` không đòi trạng thái nguồn là `inReview`: quyết định thẳng từ `waiting` không bị chặn (chưa thấy check).
- WF-03 gần như không có luật chặn; chủ yếu là màn hình đọc.
- ~~Bài SV nộp không tạo yêu cầu duyệt~~ — **đã vá 2026-11-10**: GV bấm "Đưa vào hàng chờ duyệt" (`fe/views/management/widgets/student_submissions_card.dart:148`) → `ReviewActions.queueSubmission` (`fe/review_actions.dart:127`) tạo yêu cầu `waiting` mang `fileUrl` + `submissionId`, chặn trùng. Vẫn là thao tác **tay** của GV, không tự động khi SV nộp.
- ~~AI chấm nội dung mẫu~~ — **đã vá 2026-11-10**: yêu cầu có `fileUrl` thì `runEvaluation` gọi `POST /documents/extract` (`server/app/api/documents.py:164`, chỉ nhận `res.cloudinary.com`, pdf/docx/md, trần 60 000 ký tự) rồi `ReviewPolicy.fileUnits` (`dom/review_policy.dart:84`); `fe/review_actions.dart:552-556`. Yêu cầu seed (không `fileUrl`) vẫn dùng `documentSamples`. PDF scan (ảnh, không text) trả 422 — chưa OCR.
- ~~Không có push báo SV khi GV ra quyết định~~ — **đã vá 2026-11-10**: `decideReview` gọi `notifyStudentDecision` (`fe/review_actions.dart:423`) → `POST /notifications/decision` (`server/app/api/notifications.py:386`, chỉ role `teacher`, chống gửi lặp theo cặp bài nộp + quyết định). Chỉ áp cho yêu cầu có `submissionId`.
