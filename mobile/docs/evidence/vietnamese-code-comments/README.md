# Chuẩn hóa comment tiếng Việt — Flutter Supervisor

Ngày hoàn tất: 26/10/2026 (Asia/Saigon).

## Phạm vi và trạng thái ban đầu

- Đã đọc, rà soát **101/101 file Dart trong `lib/`**.
- Có **100 file** được bổ sung hoặc chỉnh sửa comment; bổ sung **184 khối comment** giải thích logic. File duy nhất giữ nguyên nội dung là `lib/screens/management/widgets/management_shared.dart`, chỉ tập hợp các lệnh export và không có logic cần chú thích.
- Theo mẫu QC người dùng cung cấp trong cuộc trò chuyện: ưu tiên `//` ngay trên đoạn xử lý, giải thích điều kiện, trạng thái và lý do; giữ nguyên identifier và thuật ngữ kỹ thuật.
- Không có `.git` trong `D:/SRS-Review-AI-Mobile`; `git status --short` trả về `fatal: not a git repository`. Vì vậy không có baseline nhánh/commit hoặc trạng thái tracked/untracked để báo cáo. Đối chiếu bằng bản source ban đầu và SHA-256 của từng file.
- Danh sách file, dung lượng và SHA-256 trước khi sửa nằm trong [source-before.json](source-before.json); bản gốc để đối chiếu nằm trong [source-before.zip](source-before.zip). Nội dung 101 file bản gốc đã được xác minh khớp SHA-256 ghi nhận trước khi chỉnh sửa.
- Bản sao tạm ban đầu không tồn tại sau khi phiên lệnh kết thúc; đã tái dựng bản gốc từ nội dung comment ghi nhận lúc kiểm kê và các dòng code giữ nguyên, rồi xác nhận lại **101/101 SHA-256 khớp tuyệt đối** trước khi dùng làm baseline đối chiếu.
- Baseline `flutter test --reporter expanded` chạy trước khi sửa source: **213 tests đạt, exit 0**; [nhật ký](baseline-tests.log). Lần gọi ban đầu không có quyền ghi bộ nhớ đệm SDK nên chưa khởi chạy tests, đã dừng và chạy lại bằng quyền thực thi phù hợp.

## Kết quả kiểm chứng

| Kiểm tra thực tế | Kết quả | Bằng chứng |
| --- | --- | --- |
| Baseline tests | 213/213 đạt, exit 0 | [baseline-tests.log](baseline-tests.log) |
| Định dạng baseline, chỉ kiểm tra | 101 file, 0 file cần đổi, exit 0 | [baseline-format.log](baseline-format.log) |
| Đối chiếu từng dòng ngoài comment | Khớp tuyệt đối 101/101 file; không thêm/xóa file Dart | [diff-verification.json](diff-verification.json) |
| Đối chiếu token Dart bằng analyzer | Token type và lexeme khớp tuyệt đối 101/101 file, exit 0 | [token-verification.json](token-verification.json) |
| `dart format --output=none --set-exit-if-changed lib` | 101 file, 0 file cần đổi, exit 0 | [format.log](format.log) |
| `flutter analyze` | No issues found, exit 0 | [analyze.log](analyze.log) |
| `flutter test --reporter expanded` sau chỉnh sửa | Chạy toàn bộ một lần: 213/213 đạt, exit 0 | [final-tests.log](final-tests.log) |
| Rà ngôn ngữ comment | Không còn dòng comment chỉ có ký tự ASCII; đã đọc lại nội dung và giữ thuật ngữ/identifier cần thiết | [comments.patch](comments.patch) |

Đợt kiểm tra định dạng đầu tiên phát hiện hai comment mới đặt trước `finally` và `else if` chưa phù hợp cách thụt lề của Dart. Đã chuyển comment vào đúng nhánh, chỉ sửa comment, rồi kiểm tra lại đạt. Không dùng chế độ format ghi đè source.

Bộ kiểm chứng token dùng gói analyzer có sẵn trong bộ công cụ Flutter, không thêm dependency vào `pubspec.yaml`. Lần thử dùng cấu hình package của ứng dụng không tìm thấy analyzer nên đã chuyển sang cấu hình package có sẵn của Flutter SDK; lần kiểm chứng thành công được lưu trong nhật ký. Mã kiểm chứng để tham khảo: [verify-tokens.dart.txt](verify-tokens.dart.txt). Muốn chạy lại, giải nén `source-before.zip` vào `.local/vietnamese-comments-before/`, lưu mã kiểm chứng thành `.local/verify_comment_tokens.dart`, rồi chạy bằng Dart với cấu hình package của Flutter SDK.

Flutter báo có 9 package có phiên bản mới hơn ngoài ràng buộc hiện tại; đây là thông báo của bộ công cụ, không phải lỗi analyze và không thực hiện nâng cấp dependency.

Đối chiếu diff gồm **397 dòng thêm và 205 dòng bỏ**, toàn bộ là comment. Không thay đổi identifier, chuỗi thông báo lỗi, điều kiện, trạng thái, route hoặc cấu trúc Widget. Hai comment cuối dòng trong cấu hình bo góc vẫn được kiểm tra riêng. Bằng chứng token còn xác nhận mọi chuỗi, literal và toán tử giữ nguyên.

Không chỉnh sửa tests, cấu hình Firebase, dependency, source React hoặc source PoC. Không commit/push. Các lệnh Flutter chỉ được chạy để kiểm chứng, có thể tạo/cập nhật bộ nhớ đệm của công cụ.

## Các khu vực đã chú thích

| Khu vực | Nội dung đã làm rõ |
| --- | --- |
| Đăng nhập và phiên | Supervisor, phiên mô phỏng, khôi phục vai trò, thu hồi SessionScope, tạo lại điều hướng/provider khi đổi phiên |
| Riverpod và tác vụ bất đồng bộ | Phạm vi bản nháp, autoDispose, mounted, phiên còn hiệu lực, kết quả trả về sau đăng xuất, listener cuộn và hủy controller |
| Course và Repository | DTO kiểm tra kiểu, chuẩn hóa mã, chống trùng ID/mã, phân biệt tạo/cập nhật, giữ trường cũ, ranh giới chuyển sang Firestore |
| Semester, Offering, Class | Sắp học kỳ, ngày kết thúc, đợt mặc định, cấm chuyển lớp đã có nhóm, sĩ số, giới hạn nhóm, lưu trữ và xóa khi chưa có liên kết |
| Group và Project | Tên nhóm duy nhất, thành viên đúng lớp/chưa nhóm, đồng bộ nhóm–sinh viên–dự án, trưởng nhóm, dự án cùng lớp, điều kiện duyệt đăng ký |
| Document và phiên bản | Kế thừa Lab, ghép bản nộp và dữ liệu mẫu, phụ thuộc chỉ mở khi approved, phiên bản cũ, trình đọc nội dung mẫu, trạng thái đọc riêng từng phiên bản |
| Review và phản hồi | waiting → inReview, điều kiện được ghi, khóa lịch sử, nháp của tác giả, công bố phản hồi được chọn đúng yêu cầu/phiên bản, nhật ký cùng lần lưu |
| AI và thử lại | Tiêu chí bật, điểm thiếu/thủ công, điểm tham khảo, lịch sử lần chạy, loading bị gián đoạn, token, phiên và đối chiếu phiên bản |
| Rule Set | Validation, điều kiện active, ngưỡng điểm, AI bắt buộc, tăng phiên bản, bản chụp quy tắc của bản nộp, thứ tự Mục → Lớp → Đợt |
| Đồng thời và chống ghi đè | Chặn gửi lặp, revision, xung đột biểu mẫu cũ, kết quả trễ chỉ cập nhật trong phiên hợp lệ |
| Lọc và tổng hợp | AND/OR, điều kiện cha–con, khoảng thời gian đến hết phút, ngày học ghép, sắp AI có lỗi, loại trùng theo tập ID trong thống kê |
| Tải, rỗng, lỗi và thiết bị | Phân biệt trạng thái, thử lại chủ động, giữ bản nháp khi lỗi, CSV giới hạn 500 dòng, XLSX chỉ dùng mẫu, giữ con trỏ và ghép dấu khi gõ |

## Comment tiếng Anh đã chuyển sang tiếng Việt

Đã chuyển **13 khối comment tiếng Anh** tại 9 file. Danh sách đầy đủ trước/sau, kể cả các thay thế lời diễn giải pha trộn ngôn ngữ, nằm trong [comment-translations.json](comment-translations.json). Bản diff là nguồn đối chiếu cuối cùng vì một số câu còn được chỉnh lại sát hành vi thực tế sau bước dịch.

- `lib/app/session.dart`:
  - Trước: Temporary demo session, replaced by Google Sign-In during Firebase integration. Incoming/restored role values are untrusted; Mobile admits Supervisor only.
  - Sau: Phiên đăng nhập mô phỏng, dự kiến thay bằng Google Sign-In khi tích hợp Firebase. Chỉ nhận vai trò Supervisor, kể cả khi khôi phục phiên từ dữ liệu bên ngoài.
  - Trước: Revoke synchronously; pending work must fail even before the next frame.
  - Sau: Thu hồi phiên ngay để tác vụ đang chờ không tiếp tục ghi sau khi đăng xuất.
- `lib/models/session_scope.dart`:
  - Trước: A revocable client-operation lifetime, distinct from durable shared data.
  - Sau: Giới hạn thời gian hợp lệ của thao tác theo phiên; đóng phiên không xóa dữ liệu chung.
- `lib/app/providers.dart`:
  - Trước: Shared fake server store. Only committed domain data survives a session.
  - Sau: Kho mô phỏng dùng chung giữ dữ liệu đã lưu khi phiên đăng nhập kết thúc.
- `lib/services/academic/fake_academic_service.dart`:
  - Trước: Shared in-memory fake server: committed data outlives client sessions.
  - Sau: Kho mô phỏng trong bộ nhớ giữ dữ liệu đã lưu qua các phiên đăng nhập.
- `lib/repositories/academic/course_contract.dart`:
  - Trước: First migrated DTO slice. Preserve unknown legacy fields without trusting primitive casts at the data edge. Remaining aggregates migrate independently.
  - Sau: Course là phần đầu tiên có DTO kiểm tra dữ liệu đầu vào khi chuẩn bị chuyển nguồn dữ liệu. Giữ trường dữ liệu cũ chưa biết, nhưng kiểm tra kiểu trước khi đọc các trường bắt buộc.
  - Trước: Explicit create/update intent prevents an insertion from becoming an upsert.
  - Sau: Phân biệt rõ tạo mới và cập nhật để lệnh tạo không ghi đè môn học đã có.
  - Trước: Additive command seam; legacy aggregate commands remain compatible. A real adapter must authorize UID/scope, check expected version and execute this intent atomically on the server, never trust a client snapshot upload.
  - Sau: Hợp đồng lệnh Course bổ sung vẫn tương thích với cách ghi toàn bộ dữ liệu hiện tại. Khi nối Firestore, phía máy chủ phải kiểm tra UID, phạm vi và phiên bản mong đợi, rồi thực hiện lệnh nguyên tử; không tin toàn bộ dữ liệu do máy khách gửi lên.
- `lib/widgets/app_search_field.dart`:
  - Trước: Stable editing identity: provider updates never replace a focused field.
  - Sau: Giữ nguyên ô đang nhập khi provider cập nhật để không mất vị trí con trỏ.
  - Trước: Only synchronize explicit external clear/restore; preserve caret/composing on ordinary keystrokes, where controller and provider already agree.
  - Sau: Chỉ đồng bộ khi giá trị ngoài khác nội dung đang nhập, như xóa hoặc khôi phục bộ lọc. Khi gõ bình thường, giữ con trỏ và phần chữ đang ghép dấu.
- `lib/screens/account/login_screen.dart`:
  - Trước: Existing mock fields only; Firebase will replace this with Google Sign-In.
  - Sau: Thông tin điền sẵn chỉ phục vụ đăng nhập mô phỏng; dự kiến thay bằng Google Sign-In.
- `lib/models/academic/academic_projections.dart`:
  - Trước: Pure business projections shared by ViewModels; no UI dependencies.
  - Sau: Các phép tổng hợp nghiệp vụ dùng chung cho ViewModel, độc lập với giao diện.
- `lib/models/academic/project_context.dart`:
  - Trước: A linked group's class is authoritative; detached projects retain classId.
  - Sau: Dự án đã gắn nhóm lấy lớp của nhóm; dự án chưa gắn nhóm dùng classId lưu trực tiếp.

Ngoài việc dịch, đã bỏ các diễn giải theo giai đoạn cũ như “Review phase sau”, “sáu route phase 2”, “ngoài phase”; làm rõ đợt mới lấy cấu trúc từ phần tử đợt đầu tiên hiện có thay vì khẳng định là đợt trước; sửa mô tả enum mã lỗi; thay các từ không cần thiết như state, form, draft, fake, ownership, history, commit bằng lời giải thích tiếng Việt khi không phải identifier.

## Những giới hạn chưa thể mô tả như chức năng đã có

- Không có đoạn logic hiện hành nào bị bỏ trống vì chưa hiểu được ý nghĩa. Các phần trình bày đơn giản, import/export và khai báo hiển nhiên không được thêm comment máy móc.
- Chưa có adapter Firestore hoặc Google Sign-In thật trong luồng hiện tại: comment chỉ nêu ranh giới chuẩn bị và yêu cầu kiểm tra UID/phạm vi/phiên bản phía máy chủ, không khẳng định đã có xác thực Firebase.
- Kết quả AI và trình đọc tài liệu hiện dùng nội dung mẫu: chưa thể mô tả thuật toán đọc PDF/DOCX hoặc chấm nội dung tệp thật. XLSX cũng chỉ mở dữ liệu xem trước mẫu; bộ đọc CSV hiện tách dấu phân cách đơn giản, chưa xử lý trường có dấu phân cách nằm trong dấu nháy.
- Tạo lại QR dùng thời hạn mẫu cố định trong code, chưa thể mô tả là mã do máy chủ phát và tự hết hạn. Đã chú thích đúng giới hạn hiện có, không sửa logic.
- Quyền giảng viên hiện dựa trên phiên Supervisor và dữ liệu người dùng mẫu; không gán thêm lời khẳng định về kiểm tra phân công phía máy chủ chưa được triển khai.
- Không phát hiện TODO/FIXME hiện hữu trong `lib/` cần dịch hoặc bảo toàn; không thêm/bớt nhãn TODO/FIXME.
- `flutter test` ở đây là toàn bộ bộ tests mặc định trong `test/`; không chạy bộ `integration_test/` cần thiết bị vì nhiệm vụ chỉ yêu cầu `flutter test`.

## Danh sách file thay đổi

- `lib/main.dart`
- `lib/app/app_navigation.dart`
- `lib/app/app.dart`
- `lib/app/providers.dart`
- `lib/app/session.dart`
- `lib/models/counter_state.dart`
- `lib/models/session_scope.dart`
- `lib/models/academic/academic_models.dart`
- `lib/models/academic/academic_policy.dart`
- `lib/models/academic/academic_presentation.dart`
- `lib/models/academic/academic_projections.dart`
- `lib/models/academic/management_queries.dart`
- `lib/models/academic/project_context.dart`
- `lib/models/academic/review_policy.dart`
- `lib/models/dashboard/dashboard_snapshot.dart`
- `lib/models/dashboard/dashboard_state.dart`
- `lib/repositories/counter_repository.dart`
- `lib/repositories/notification_repository.dart`
- `lib/repositories/academic/academic_repository.dart`
- `lib/repositories/academic/course_contract.dart`
- `lib/repositories/academic/fake_academic_repository.dart`
- `lib/repositories/academic/student_device_gateway.dart`
- `lib/repositories/dashboard/dashboard_repository.dart`
- `lib/repositories/dashboard/fake_dashboard_repository.dart`
- `lib/screens/demo_screen.dart`
- `lib/screens/navigation_destination_screen.dart`
- `lib/screens/academic/class_screens.dart`
- `lib/screens/academic/course_screens.dart`
- `lib/screens/academic/directory_screens.dart`
- `lib/screens/academic/offering_detail_screen.dart`
- `lib/screens/academic/widgets/academic_form_sheet.dart`
- `lib/screens/academic/widgets/academic_page.dart`
- `lib/screens/academic/widgets/class_card.dart`
- `lib/screens/academic/widgets/class_filter_bar.dart`
- `lib/screens/academic/widgets/class_overview.dart`
- `lib/screens/academic/widgets/class_review_preview.dart`
- `lib/screens/academic/widgets/group_summary_card.dart`
- `lib/screens/academic/widgets/lab_editor.dart`
- `lib/screens/academic/widgets/rule_set_panel.dart`
- `lib/screens/academic/widgets/student_enrollment_sheet.dart`
- `lib/screens/account/account_screens.dart`
- `lib/screens/account/login_screen.dart`
- `lib/screens/dashboard/dashboard_screen.dart`
- `lib/screens/dashboard/widgets/dashboard_heading.dart`
- `lib/screens/dashboard/widgets/dashboard_review_row.dart`
- `lib/screens/dashboard/widgets/dashboard_secondary_sections.dart`
- `lib/screens/dashboard/widgets/dashboard_stats.dart`
- `lib/screens/dashboard/widgets/dashboard_tasks.dart`
- `lib/screens/management/document_screens.dart`
- `lib/screens/management/group_screens.dart`
- `lib/screens/management/project_registrations_screen.dart`
- `lib/screens/management/project_screens.dart`
- `lib/screens/management/review_history_screens.dart`
- `lib/screens/management/review_screens.dart`
- `lib/screens/management/widgets/ai_review_panel.dart`
- `lib/screens/management/widgets/document_card.dart`
- `lib/screens/management/widgets/management_filter_bar.dart`
- `lib/screens/management/widgets/management_form_sheet.dart`
- `lib/screens/management/widgets/project_form_fields.dart`
- `lib/screens/management/widgets/review_feedback.dart`
- `lib/screens/management/widgets/sample_document_reader.dart`
- `lib/services/demo_counter_service.dart`
- `lib/services/academic/fake_academic_service.dart`
- `lib/services/academic/student_import_service.dart`
- `lib/services/dashboard/fake_dashboard_service.dart`
- `lib/theme/app_colors.dart`
- `lib/theme/app_metrics.dart`
- `lib/theme/app_radius.dart`
- `lib/theme/app_shadows.dart`
- `lib/theme/app_spacing.dart`
- `lib/theme/app_theme.dart`
- `lib/theme/app_typography.dart`
- `lib/viewmodels/counter_view_model.dart`
- `lib/viewmodels/academic/academic_form_view_model.dart`
- `lib/viewmodels/academic/academic_view_model.dart`
- `lib/viewmodels/academic/class_filter_view_model.dart`
- `lib/viewmodels/academic/directory_view_model.dart`
- `lib/viewmodels/academic/document_reader_view_model.dart`
- `lib/viewmodels/academic/management_actions.dart`
- `lib/viewmodels/academic/management_form_view_model.dart`
- `lib/viewmodels/academic/management_list_view_model.dart`
- `lib/viewmodels/academic/review_actions.dart`
- `lib/viewmodels/academic/review_panel_view_model.dart`
- `lib/viewmodels/academic/student_enrollment_view_model.dart`
- `lib/viewmodels/dashboard/dashboard_view_model.dart`
- `lib/widgets/app_academic_layout.dart`
- `lib/widgets/app_badge.dart`
- `lib/widgets/app_bottom_navigation.dart`
- `lib/widgets/app_button.dart`
- `lib/widgets/app_card.dart`
- `lib/widgets/app_disclosure.dart`
- `lib/widgets/app_filter_controls.dart`
- `lib/widgets/app_icon.dart`
- `lib/widgets/app_meta_grid.dart`
- `lib/widgets/app_search_field.dart`
- `lib/widgets/app_states.dart`
- `lib/widgets/app_status_tracks.dart`
- `lib/widgets/demo_counter_value.dart`
- `lib/widgets/mobile_header.dart`
- `lib/widgets/stat_card.dart`

## Tài liệu đối chiếu

- [Danh sách và mã băm trước sửa](source-before.json), [sau sửa](source-after.json).
- [Bản source baseline](source-before.zip), [diff đầy đủ](comments.patch).
- [Kiểm tra dòng ngoài comment](diff-verification.json), [kiểm tra token](token-verification.json).
- Các file `*.exit.txt` ghi mã thoát thực tế của từng lệnh; các file `*.log` ghi kết quả thực thi.
