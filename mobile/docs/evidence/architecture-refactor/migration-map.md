# File migration map

Bản phân loại trước khi sửa nằm trong [migration-plan.json](migration-plan.json). Bảng này ghi vị trí triển khai cuối; đường dẫn cũ của 76 file được giữ bằng export chuyển tiếp để không sửa 213 tests ban đầu. Không tồn tại hai bản triển khai độc lập.

| Trước | Triển khai sau | Phân loại thực tế | Lý do |
| --- | --- | --- | --- |
| `lib/app/app.dart` | `lib/app/app.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/app/app_navigation.dart` | `lib/core/navigation/app_navigation.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/app/providers.dart` | `lib/core/di/data_providers.dart` | cần tách trách nhiệm | Đổi vị trí DI; các provider giữ danh tính công khai qua facade. |
| `lib/app/session.dart` | `lib/core/session/session_view_model.dart` | cần tách trách nhiệm | Tách AppSession thuần Dart khỏi vòng đời Riverpod. |
| `lib/main.dart` | `lib/main.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/academic/academic_models.dart` | `lib/core/domain/academic/academic_models.dart` | cần tách trách nhiệm | Gom các phần truy vấn và minh họa cùng thư viện để bỏ import vòng, giữ thân khai báo. |
| `lib/models/academic/academic_policy.dart` | `lib/core/domain/academic/academic_policy.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/academic/academic_presentation.dart` | `lib/core/domain/academic/academic_presentation.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/academic/academic_projections.dart` | `lib/core/domain/academic/academic_projections.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/academic/management_queries.dart` | `lib/core/domain/academic/management_queries.dart` | cần tách trách nhiệm | Đổi thành part của thư viện học vụ; không đổi quy tắc truy vấn. |
| `lib/models/academic/project_context.dart` | `lib/core/domain/academic/project_context.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/academic/review_policy.dart` | `lib/core/domain/academic/review_policy.dart` | cần tách trách nhiệm | Đổi thành part của thư viện học vụ; không đổi quy tắc AI minh họa. |
| `lib/models/counter_state.dart` | `lib/core/domain/counter_state.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/dashboard/dashboard_snapshot.dart` | `lib/core/domain/dashboard/dashboard_snapshot.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/dashboard/dashboard_state.dart` | `lib/core/domain/dashboard/dashboard_state.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/models/session_scope.dart` | `lib/core/domain/session_scope.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/academic/academic_repository.dart` | `lib/core/contracts/academic/academic_repository.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/academic/course_contract.dart` | `lib/core/contracts/academic/course_contract.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/academic/fake_academic_repository.dart` | `lib/features/academic/data/repositories/fake_academic_repository.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/academic/student_device_gateway.dart` | `lib/core/contracts/academic/student_device_gateway.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/counter_repository.dart` | `lib/core/contracts/counter_repository.dart` | cần tách trách nhiệm | Tách contract thuần Dart và DemoCounterRepository. |
| `lib/repositories/dashboard/dashboard_repository.dart` | `lib/core/contracts/dashboard/dashboard_repository.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/dashboard/fake_dashboard_repository.dart` | `lib/features/dashboard/data/repositories/fake_dashboard_repository.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/repositories/notification_repository.dart` | `lib/features/account/data/notification_repository.dart` | cần tách trách nhiệm | Tách contract, Service, Repository, DI và ViewModel thông báo. |
| `lib/screens/academic/class_screens.dart` | `lib/features/academic/presentation/views/class_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/course_screens.dart` | `lib/features/academic/presentation/views/course_screens.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/academic/directory_screens.dart` | `lib/features/academic/presentation/views/directory_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/offering_detail_screen.dart` | `lib/features/academic/presentation/views/offering_detail_screen.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/widgets/academic_form_sheet.dart` | `lib/features/academic/presentation/views/widgets/academic_form_sheet.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/widgets/academic_page.dart` | `lib/features/academic/presentation/views/widgets/academic_page.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/academic/widgets/class_card.dart` | `lib/features/academic/presentation/views/widgets/class_card.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/academic/widgets/class_filter_bar.dart` | `lib/features/academic/presentation/views/widgets/class_filter_bar.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/widgets/class_overview.dart` | `lib/features/academic/presentation/views/widgets/class_overview.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/academic/widgets/class_review_preview.dart` | `lib/features/academic/presentation/views/widgets/class_review_preview.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/academic/widgets/group_summary_card.dart` | `lib/features/academic/presentation/views/widgets/group_summary_card.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/widgets/lab_editor.dart` | `lib/features/academic/presentation/views/widgets/lab_editor.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/widgets/rule_set_panel.dart` | `lib/features/academic/presentation/views/widgets/rule_set_panel.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/academic/widgets/student_enrollment_sheet.dart` | `lib/features/academic/presentation/views/widgets/student_enrollment_sheet.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/account/account_screens.dart` | `lib/features/account/presentation/views/account_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/account/login_screen.dart` | `lib/features/account/presentation/views/login_screen.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/dashboard/dashboard_screen.dart` | `lib/features/dashboard/presentation/views/dashboard_screen.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/dashboard/widgets/dashboard_heading.dart` | `lib/features/dashboard/presentation/views/widgets/dashboard_heading.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/dashboard/widgets/dashboard_review_row.dart` | `lib/features/dashboard/presentation/views/widgets/dashboard_review_row.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/dashboard/widgets/dashboard_secondary_sections.dart` | `lib/features/dashboard/presentation/views/widgets/dashboard_secondary_sections.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/dashboard/widgets/dashboard_stats.dart` | `lib/features/dashboard/presentation/views/widgets/dashboard_stats.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/dashboard/widgets/dashboard_tasks.dart` | `lib/features/dashboard/presentation/views/widgets/dashboard_tasks.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/demo_screen.dart` | `lib/features/demo/presentation/views/demo_screen.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/screens/management/document_screens.dart` | `lib/features/academic/presentation/views/management/document_screens.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/management/group_screens.dart` | `lib/features/academic/presentation/views/management/group_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/project_registrations_screen.dart` | `lib/features/academic/presentation/views/management/project_registrations_screen.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/project_screens.dart` | `lib/features/academic/presentation/views/management/project_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/review_history_screens.dart` | `lib/features/academic/presentation/views/management/review_history_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/review_screens.dart` | `lib/features/academic/presentation/views/management/review_screens.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/widgets/ai_review_panel.dart` | `lib/features/academic/presentation/views/management/widgets/ai_review_panel.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/widgets/document_card.dart` | `lib/features/academic/presentation/views/management/widgets/document_card.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/management/widgets/management_filter_bar.dart` | `lib/features/academic/presentation/views/management/widgets/management_filter_bar.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/widgets/management_form_sheet.dart` | `lib/features/academic/presentation/views/management/widgets/management_form_sheet.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/widgets/management_shared.dart` | `lib/features/academic/presentation/views/management/widgets/management_shared.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/widgets/project_form_fields.dart` | `lib/features/academic/presentation/views/management/widgets/project_form_fields.dart` | move-only | Chỉ đổi vị trí/import, giữ cách dựng giao diện. |
| `lib/screens/management/widgets/review_feedback.dart` | `lib/features/academic/presentation/views/management/widgets/review_feedback.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/management/widgets/sample_document_reader.dart` | `lib/features/academic/presentation/views/management/widgets/sample_document_reader.dart` | cần tách trách nhiệm | View theo feature; các phép chiếu và trạng thái đã được chuyển sang ViewModel khi có. |
| `lib/screens/navigation_destination_screen.dart` | `lib/screens/navigation_destination_screen.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/services/academic/fake_academic_service.dart` | `lib/features/academic/data/services/fake_academic_service.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/services/academic/student_import_service.dart` | `lib/features/academic/data/services/student_import_service.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/services/dashboard/fake_dashboard_service.dart` | `lib/features/dashboard/data/services/fake_dashboard_service.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/services/demo_counter_service.dart` | `lib/features/demo/data/services/demo_counter_service.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_colors.dart` | `lib/theme/app_colors.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_metrics.dart` | `lib/theme/app_metrics.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_radius.dart` | `lib/theme/app_radius.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_shadows.dart` | `lib/theme/app_shadows.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_spacing.dart` | `lib/theme/app_spacing.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_theme.dart` | `lib/theme/app_theme.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/theme/app_typography.dart` | `lib/theme/app_typography.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/viewmodels/academic/academic_form_view_model.dart` | `lib/features/academic/presentation/viewmodels/academic_form_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/academic/academic_view_model.dart` | `lib/features/academic/presentation/viewmodels/academic_view_model.dart` | cần tách trách nhiệm | Gom command parts và phát tín hiệu cập nhật thay phụ thuộc DashboardViewModel. |
| `lib/viewmodels/academic/class_filter_view_model.dart` | `lib/features/academic/presentation/viewmodels/class_filter_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/academic/directory_view_model.dart` | `lib/features/academic/presentation/viewmodels/directory_view_model.dart` | cần tách trách nhiệm | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/viewmodels/academic/document_reader_view_model.dart` | `lib/features/academic/presentation/viewmodels/document_reader_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/academic/management_actions.dart` | `lib/features/academic/presentation/viewmodels/management_actions.dart` | cần tách trách nhiệm | Part của AcademicViewModel để tránh import ngược vòng; giữ lệnh ghi. |
| `lib/viewmodels/academic/management_form_view_model.dart` | `lib/features/academic/presentation/viewmodels/management_form_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/academic/management_list_view_model.dart` | `lib/features/academic/presentation/viewmodels/management_list_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/academic/review_actions.dart` | `lib/features/academic/presentation/viewmodels/review_actions.dart` | cần tách trách nhiệm | Part của AcademicViewModel; giữ lệnh đánh giá, phiên bản và nhật ký. |
| `lib/viewmodels/academic/review_panel_view_model.dart` | `lib/features/academic/presentation/viewmodels/review_panel_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/academic/student_enrollment_view_model.dart` | `lib/features/academic/presentation/viewmodels/student_enrollment_view_model.dart` | cần tách trách nhiệm | Bổ sung phép chiếu/trạng thái đầu ra thay logic nằm trong View. |
| `lib/viewmodels/counter_view_model.dart` | `lib/features/demo/presentation/viewmodels/counter_view_model.dart` | move-only | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/viewmodels/dashboard/dashboard_view_model.dart` | `lib/features/dashboard/presentation/viewmodels/dashboard_view_model.dart` | cần tách trách nhiệm | Theo dõi tín hiệu cập nhật trong ProviderScope và chuẩn bị dữ liệu tóm tắt. |
| `lib/widgets/app_academic_layout.dart` | `lib/widgets/app_academic_layout.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_badge.dart` | `lib/widgets/app_badge.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_bottom_navigation.dart` | `lib/widgets/app_bottom_navigation.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_button.dart` | `lib/widgets/app_button.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_card.dart` | `lib/widgets/app_card.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_disclosure.dart` | `lib/widgets/app_disclosure.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_filter_controls.dart` | `lib/widgets/app_filter_controls.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_icon.dart` | `lib/widgets/app_icon.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_meta_grid.dart` | `lib/widgets/app_meta_grid.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_search_field.dart` | `lib/widgets/app_search_field.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_states.dart` | `lib/widgets/app_states.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/app_status_tracks.dart` | `lib/widgets/app_status_tracks.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/demo_counter_value.dart` | `lib/widgets/demo_counter_value.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/mobile_header.dart` | `lib/widgets/mobile_header.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |
| `lib/widgets/stat_card.dart` | `lib/widgets/stat_card.dart` | giữ nguyên | Giữ nguyên thân triển khai, chỉ cập nhật import nếu cần. |

Các file bổ sung: `core/domain/app_session.dart`, `core/domain/notification_policy.dart`, `core/contracts/notification_repository.dart`, `core/state/*`, `core/di/notification_providers.dart`, `features/demo/data/repositories/demo_counter_repository.dart`, `features/account/data/services/notification_service.dart`, các ViewModel trình bày mới của account/academic, `theme/app_feature_metrics.dart` và `test/architecture_refactor_test.dart`. Danh sách tuyệt đối của source cuối nằm trong `source-after.json`.

Các facade cũ không được code triển khai mới import ngược lại; chúng chỉ phục vụ tương thích mã gọi hiện hữu. Khi chuyển sang monorepo Final có thể xóa facade sau một đợt cập nhật import riêng có kiểm thử.
