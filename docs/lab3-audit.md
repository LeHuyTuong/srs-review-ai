# Kiểm định Lab 3 PRM393 — Giai đoạn 1 (chỉ đọc)

Ngày kiểm: 03/11/2026. Người kiểm: Claude Code (auditor). Đề bài đối chiếu: `docs/PRM393 - Lab 3 From Design to Working App with Flutter and Firebase.pdf` (bản MobAI, 17 trang) ở thư mục `F:\study\PRM\docs`.

Quy ước đường dẫn: nếu không ghi khác, đường dẫn tính từ gốc repo `srs-review-ai/`. Đường dẫn bắt đầu bằng `LAB3/` hoặc `AI-Review--ui/` tính từ `F:\study\PRM\`. Ghi chú: phần prompt `[ĐIỀN CHỦ ĐỀ]` và `[LUỒNG 1..3]` để trống, nên chủ đề và 3 luồng được lấy từ tài liệu Lab 2 `AI-Review--ui/ux/user-flow.md:103-170`.

- **Chủ đề:** Project Review AI, một ứng dụng giúp giảng viên (Supervisor) quản lý học vụ và duyệt tài liệu SRS của sinh viên, có AI hỗ trợ.
- **F1:** Quản lý học vụ và tạo dự án.
- **F2:** Supervisor duyệt có AI hỗ trợ, gồm nhánh lỗi AI và Thử lại.
- **F3:** Sinh viên nộp tài liệu, nộp lại bản sửa và được duyệt, gồm nhánh tệp không hợp lệ và chọn lại.

---

## 1. Tóm tắt điều hành

Ứng dụng Flutter `mobile/` có giao diện Supervisor khá hoàn chỉnh: 25 màn hình, Riverpod/MVVM và token theme sạch. Tuy vậy, **toàn bộ dữ liệu là fixture JSON trong bộ nhớ** và **chưa tích hợp dịch vụ Firebase nào ngoài `firebase_core`**. Ngoài ra **Student flow (F3) không tồn tại**, chưa có MobAI test và chưa có tài liệu nộp bài. Ước tính hoàn thành theo rubric (100 điểm):

| Nhóm | Điểm tối đa | Ước tính | % | Lý do chính |
|---|---|---|---|---|
| Functional | 25 | ~8 | ~32% | Đủ màn Supervisor; flow chạy trên dữ liệu giả; không Firestore, không real-time, thiếu F3 |
| Firebase | 25 | ~1 | ~4% | Chỉ `Firebase.initializeApp`; rules nằm ở project khác và chưa theo owner-only |
| Architecture | 10 | ~7.5 | ~75% | Riverpod nhất quán, View không gọi SDK; nhưng services chưa phải lớp Firebase |
| Fidelity | 10 | ~4 | ~40% | Token gần như sạch; thiếu `fidelity-check.md`, accessibility chưa đo lại trên app thật |
| MobAI | 15 | 0 | 0% | Không có `mobai_tests/`, không có healing/bug exercise |
| Code review | 5 | 0 | 0% | `LAB3/.../code-review.md` chỉ là template |
| AI log + handoff | 5 | 0 | 0% | Không có `implementation-ai-log.md`, `handoff-gaps.md` |
| Report + video | 5 | 0 | 0% | `LAB3/PRM393_Lab03/report/`, `slides/` rỗng |
| **Tổng** | **100** | **~20** | | |

**Chặn nộp bài:** (1) Dart SDK máy hiện tại (3.13.3) thấp hơn ràng buộc `sdk: ^3.13.4`, nên `pub get` sẽ lỗi. (2) Hồ sơ Chrome (Cookies, Login Data) đã bị commit vào git. (3) Chưa có repo `PRM393_Lab03_<StudentID>` có lịch sử commit và PR riêng cho mobile.

---

## 2. Bảng kiểm kê theo mục A–G

### 2.0 Cấu trúc repo (bước 1)

| Phần | Vị trí | Ghi chú |
|---|---|---|
| **Mobile Flutter (bài nộp)** | `srs-review-ai/mobile/` | package `srs_review_ai_mobile` (`mobile/pubspec.yaml:1`); 194 file trong `lib/` |
| Flutter desktop (ngoài phạm vi) | `srs-review-ai/desktop/` | Gọi server Python qua `API_BASE_URL` (`desktop/lib/core/app_config.dart:20-30`) |
| Server Python (FastAPI) | `srs-review-ai/server/` | Endpoints trong `server/app/api/*.py`; có `server/.env` (đã ignore, `.gitignore:2`) |
| React demo Lab 2 | `AI-Review--ui/` (repo git riêng) | `src/pages/**`, tài liệu Lab 2: `flutter-handoff.md`, `DESIGN.md`, `ux/user-flow.md` |
| Khung tài liệu Lab 3 (không phải git) | `LAB3/PRM393_Lab03/` | `firebase/firestore.rules`, `docs/analytics-plan.md`, `docs/test-plan.md` (theo bản ARTEMIS), `report/`, `slides/` rỗng |
| Rác/tạo tự động | `srs-review-ai/app/` | 260 file tracked, gồm `app/.dart_tool/chrome-device/**` (xem vấn đề B1) |

Cấu trúc `mobile/lib/`: phần triển khai thật nằm trong `lib/features/<feature>/{data,presentation}` và `lib/core/`. Các thư mục `lib/screens/`, `lib/viewmodels/`, `lib/services/`, `lib/models/`, `lib/repositories/` chỉ chứa **file re-export 2 dòng** (ví dụ `lib/screens/academic/class_screens.dart:1-2`). Thư mục `lib/utils/` không tồn tại.

### 2.1 Dependency (bước 2) — `mobile/pubspec.yaml`

| Có | Dòng |
|---|---|
| `flutter_riverpod: ^3.4.3` | 37 |
| `firebase_core: any` (không ghim phiên bản) | 43 |
| `flutter_svg`, `file_selector`, `qr_flutter`, `flutter_localizations` | 38-42 |
| `sdk: ^3.13.4` | 22 |

**Thiếu so với mục B/C:** `firebase_auth`, `google_sign_in`, `cloud_firestore`, `firebase_messaging`, `flutter_local_notifications` (để hiện thông báo khi app đang mở), `firebase_remote_config`, `firebase_crashlytics`, `firebase_analytics`, `pdf` (+ `printing` hoặc `path_provider`), `http` hoặc `dio` (để upload Cloudinary), `url_launcher` (để mở URL PDF). Không có `provider`/`bloc`/`get`, nên state management không bị trộn.

### A. Chức năng

| # | Yêu cầu | Trạng thái | Bằng chứng | Ghi chú |
|---|---|---|---|---|
| A1 | ≥8 màn + Login + Profile; nav/Back giống prototype | **MỘT PHẦN** | Route table `mobile/lib/app/app.dart:50-87`; bottom nav 5 tab `mobile/lib/widgets/app_bottom_navigation.dart:20-24`; `AppNavigation.open` `mobile/lib/core/navigation/app_navigation.dart:5-11` | 25 màn Supervisor. **Thiếu toàn bộ màn Student ST01–ST04, StudentDocumentDetail, StudentVersions** (`AI-Review--ui/ux/user-flow.md:77-82`). Back chưa đối chiếu với ma trận Back `user-flow.md:303` → chưa xác minh được |
| A2 | 3 luồng end-to-end trên dữ liệu thật + nhánh lỗi | **THIẾU** | Dữ liệu: `mobile/lib/features/academic/data/services/fake_academic_service.dart:21`; F3 bị chặn bởi `mobile/lib/core/session/session_view_model.dart:38-40` (chỉ Supervisor) | F1/F2 chạy trên fixture; nhánh lỗi AI của F2 **không kích hoạt được từ UI** (`review_panel_view_model.dart:69` luôn gọi `runEvaluation(id)` với `simulateError=false`, xem `review_actions.dart:278`) |
| A3 | Loading/empty/error do dữ liệu thật | **MỘT PHẦN** | `mobile/lib/core/state/screen_state.dart:2`; `mobile/lib/features/academic/presentation/views/widgets/academic_page.dart:47-52`; `mobile/lib/widgets/app_states.dart:12,120,139` | Cơ chế đúng, nhưng lỗi chỉ xảy ra khi fixture hỏng; chưa có lỗi mạng hay permission-denied thật |
| A4 | CRUD entity chính + query lọc/sắp xếp + listener + seed | **MỘT PHẦN** | Project: `saveProject` `management_actions.dart:127`, `deleteProject` `:247`, nút Xóa/Lưu trữ `project_screens.dart:141,160`; sort `management_list_view_model.dart:78` | CRUD và lọc/sắp xếp chỉ trong bộ nhớ (`fake_academic_service.dart:40-71`); **không có snapshots listener**; seed = `assets/fixtures/academic.json` |

#### Bảng màn hình (bước 3)

Mọi màn đọc dữ liệu từ **mock JSON** (`assets/fixtures/*.json` qua `FakeAcademicService` hoặc `NotificationService`). Không màn nào gọi HTTP tới Python hay Firestore.

| File (dưới `mobile/lib/features/`) | Class | Route | ViewModel/Provider |
|---|---|---|---|
| account/presentation/views/login_screen.dart:17 | LoginScreen | (builder khi chưa có phiên) | `loginViewModelProvider` → `sessionProvider` |
| dashboard/presentation/views/dashboard_screen.dart:18 | DashboardScreen | `/`, `/dashboard` | `dashboardViewModelProvider` |
| account/presentation/views/account_screens.dart:7 | ProfileScreen | `/profile` | `academicPageProvider` (AcademicPage), `sessionProvider` |
| account/presentation/views/account_screens.dart:129 | NotificationsScreen | `/notifications` | `notificationScreenProvider`, `notificationTabProvider` |
| academic/presentation/views/directory_screens.dart:8 | SemesterListScreen | `/semesters` | `academicViewModelProvider` |
| academic/presentation/views/directory_screens.dart:135 | StudentDirectoryScreen | `/students` | `studentDirectoryProvider` |
| academic/presentation/views/course_screens.dart:20 | CourseListScreen | `/courses` | `academicPageProvider` |
| academic/presentation/views/course_screens.dart:182 | CourseDetailScreen | `/courses/:id` | `academicPageProvider` |
| academic/presentation/views/course_screens.dart:234 | RuleSetSelectionScreen | `/rule-sets` | `academicPageProvider` |
| academic/presentation/views/offering_detail_screen.dart:25 | OfferingDetailScreen | `/course-offerings/:id` | `academicFormProvider`, `academicUiProvider` |
| academic/presentation/views/class_screens.dart:32 | ClassListScreen | `/classes` | `classFilterProvider`, `academicUiProvider` |
| academic/presentation/views/class_screens.dart:70 | ClassDetailScreen | `/classes/:id` | `academicUiProvider` |
| academic/presentation/views/management/group_screens.dart:6 | GroupListScreen | `/groups` | `academicPageProvider` |
| academic/presentation/views/management/group_screens.dart:76 | GroupDetailScreen | `/groups/:id` | `academicViewModelProvider`, `managementFormProvider` |
| academic/presentation/views/management/project_screens.dart:10 | ProjectListScreen | `/projects` | `managementListProvider` |
| academic/presentation/views/management/project_screens.dart:101 | ProjectDetailScreen | `/projects/:id` | `managementListProvider` |
| academic/presentation/views/management/document_screens.dart:89 | ProjectDocumentsScreen | `/projects/:id/documents` | `managementListProvider` |
| academic/presentation/views/management/project_registrations_screen.dart:7 | ProjectRegistrationsScreen | `/project-registrations` | `managementListProvider`, `managementFormProvider` |
| academic/presentation/views/management/document_screens.dart:7 | DocumentListScreen | `/documents` | `managementListProvider` |
| academic/presentation/views/management/review_screens.dart:12 | ReviewListScreen | `/reviews` | `managementListProvider` |
| academic/presentation/views/management/review_screens.dart:54 | ReviewWorkspaceScreen | `/reviews/:id` | `managementListProvider`, `reviewPanelProvider` |
| academic/presentation/views/management/review_history_screens.dart:10 | AiResultScreen | `/reviews/:id/ai-result` | `academicPageProvider` |
| academic/presentation/views/management/review_history_screens.dart:81 | VersionHistoryScreen | `/reviews/:id/versions` | `managementListProvider` |
| academic/presentation/views/management/review_history_screens.dart:264 | ReviewHistoryScreen | `/reviews/:id/history` | `academicPageProvider` |
| academic/presentation/views/management/review_history_screens.dart:354 | ReviewHistoryIndexScreen | `/review-history` | `managementListProvider` |
| demo/presentation/views/demo_screen.dart:8 | DemoScreen (counter) | không có route | `counterViewModelProvider` — nên xóa |
| `lib/screens/navigation_destination_screen.dart:11` | NavigationDestinationScreen | fallback 404 | — |

### B. Firebase

| # | Dịch vụ | Trạng thái | Bằng chứng | Ghi chú |
|---|---|---|---|---|
| B0 | Khởi tạo | ĐỦ | `mobile/lib/main.dart:11`; `mobile/lib/firebase_options.dart:53-59`; plugin `com.google.gms.google-services` `mobile/android/app/build.gradle.kts:4`, `mobile/android/settings.gradle.kts:24` | Project `srs-review-ai-ff68b` (`mobile/firebase.json:6`) |
| B1 | Auth Google | **THIẾU** | Login giả `mobile/lib/core/session/session_view_model.dart:37-51`; email/mật khẩu điền sẵn `login_screen.dart:25-26`; ghi chú "Đăng nhập mô phỏng" `login_screen.dart:93-96`; **`"oauth_client": []`** `mobile/android/app/google-services.json:15` | `oauth_client` rỗng nghĩa là SHA-1 chưa đăng ký và Google Sign-In sẽ lỗi `ApiException: 10`. Profile lấy tên/email từ fixture (`account_screens.dart:13-15`, `assets/fixtures/academic.json:2883`), dùng avatar chữ cái thay ảnh (`:26-28`). Chặn màn khi chưa đăng nhập đã có (`app.dart:38-48`) |
| B2 | Firestore + rules | **THIẾU** | Không có `cloud_firestore`; rules chỉ ở `LAB3/PRM393_Lab03/firebase/firestore.rules` cho project **`prm-srs-ai`** (`LAB3/PRM393_Lab03/firebase/.firebaserc:3`) | **Không trùng project** với app (`srs-review-ai-ff68b`). Xem mục 2.2 |
| B3 | PDF + Cloudinary | **THIẾU** | Không có package `pdf`/`http`; không có service upload | — |
| B4 | FCM | **THIẾU** | `mobile/android/app/src/main/AndroidManifest.xml:1-45` không có `POST_NOTIFICATIONS`; Notification Center hiện đọc `assets/fixtures/notifications.json` (`notification_service.dart:10`) | Màn Notification Center đã có nên tái dùng được; điều hướng khi chạm thông báo chưa có |
| B5 | Remote Config | **THIẾU** (có default) | Default `LAB3/PRM393_Lab03/firebase/remote-config-defaults.json:2-13` (`ai_review_enabled`, `review_queue_page_size`) | Chưa dùng trong app; Profile chưa hiển thị |
| B6 | Crashlytics | **THIẾU** | `build.gradle.kts:1-8` không có plugin `com.google.firebase.crashlytics` | Profile chưa có nút demo |
| B7 | Analytics | **MỘT PHẦN (chỉ plan)** | `LAB3/PRM393_Lab03/docs/analytics-plan.md:5-19` | Plan thiếu `screen_view` và `export_pdf` (đang đặt tên `export_report`, `:19`); `view_project` có tham số `project_name` (`:10`), dễ chứa tên người hoặc tên nhóm, nên bỏ. Không có lời gọi `logEvent` nào trong `lib/` |
| — | minSdk | Chưa xác minh | `build.gradle.kts:25` `minSdk = flutter.minSdkVersion` | Mặc định Flutter hiện là 21 → đủ cho Firebase hiện tại. Kiểm bằng `flutter build apk --debug` sau khi thêm package |

### C. Kiến trúc

| Yêu cầu | Trạng thái | Bằng chứng | Ghi chú |
|---|---|---|---|
| Riverpod nhất quán | ĐỦ | `pubspec.yaml:37`; không có provider/bloc/get | setState chỉ cho UI cục bộ: `directory_screens.dart:311` (lựa chọn trong picker), `widgets/app_disclosure.dart:68` (mở/đóng) → chấp nhận được |
| Cấu trúc thư mục | MỘT PHẦN | `lib/screens/**` là shim re-export (vd `lib/screens/academic/class_screens.dart:1-2`); không có `lib/utils/` | Giám khảo mở `screens/` sẽ thấy file rỗng. Nên chuyển code thật về đúng `screens/ viewmodels/ services/ models/` hoặc ghi rõ lý do trong README |
| View không gọi Firebase/HTTP | ĐỦ (hiện tại) | grep `firebase|cloud_firestore|http|dio|/services/|/data/` trong `views/`, `widgets/`, `screens/` → 0 kết quả | Phải giữ khi thêm Firebase |
| Chỉ services gọi SDK | Chưa áp dụng | Services hiện đọc asset (`fake_*_service.dart`) | Cần tạo `AuthService`, `FirestoreService`, `FileStorageService`, ... |
| ViewModel không có BuildContext | ĐỦ | Chỉ `core/navigation/app_navigation.dart:5` nhận `BuildContext` (helper điều hướng, không phải VM) | — |
| Model Dart thuần + toMap/fromMap | MỘT PHẦN | `core/domain/academic/academic_models.dart` (368 dòng), codec `AcademicSnapshotCodec` dùng trong `fake_academic_service.dart:20` | Model bọc `Map` (`AcademicRecord(v as AcademicJson)`), chưa có `fromFirestore`. Toàn app là **một snapshot JSON lớn**, không thể map 1-1 sang document Firestore |
| Business logic trong build() | MỘT PHẦN | `ProfileScreen` tự đọc `s.data['currentUser']` (`account_screens.dart:13-15`); lọc thông báo bằng regex nằm trong service (`notification_service.dart:13-31`) | Mức nhỏ |

### D. Design fidelity

| Yêu cầu | Trạng thái | Bằng chứng | Ghi chú |
|---|---|---|---|
| Token chỉ từ `lib/theme` | ĐỦ (ít ngoại lệ) | `Color(0x` ngoài theme: 0; `fontSize:` số: 0; `EdgeInsets` số: 0. Ngoại lệ: `Radius.circular(6)` `sample_document_reader.dart:373`; `Rect.fromCenter(... width: 120, height: 24)` `:401,:405`; `height: 1` `:362`; `width: 2` `widgets/app_academic_layout.dart:83`; `Colors.transparent` ×3 (`app_academic_layout.dart:84`, `app_button.dart:115,130`) | Theme: `lib/theme/app_colors.dart`, `app_spacing.dart`, `app_radius.dart`, `app_typography.dart`, `app_theme.dart`. Ghi các ngoại lệ vào fidelity-check |
| Component tái sử dụng | ĐỦ (sơ bộ) | `lib/widgets/` 16 widget (AppButton, AppCard, AppBadge, AppStates, MobileHeader, AppBottomNavigation, ...) | Chưa đối chiếu 1-1 với 9 component Lab 2 (`AI-Review--ui/figma-svg/output/05-components/`) → chưa xác minh được |
| handoff-gaps / design-change-log / fidelity-check | **THIẾU** | Không tồn tại ở đâu trong `F:\study\PRM` | Có tư liệu thô: `mobile/docs/design-traceability.md`, `mobile/docs/phase*-ui-report.md` |

### E. Kỹ thuật chung

| Yêu cầu | Trạng thái | Bằng chứng | Ghi chú |
|---|---|---|---|
| `flutter analyze` | **KHÔNG CHẠY ĐƯỢC CÓ Ý NGHĨA** | `flutter analyze --no-pub` → 8975 issues, toàn bộ là `uri_does_not_exist` vì thiếu `.dart_tool/` (chưa `pub get`) | Bằng chứng cũ ghi exit 0: `mobile/docs/evidence/architecture-refactor/final-analyze.exit.txt`. Máy có Flutter 3.47.4 / **Dart 3.13.3** < `sdk: ^3.13.4` (`pubspec.yaml:22`) nên `pub get` sẽ thất bại |
| `dart format` | **MỘT PHẦN** | `dart format --output=none --set-exit-if-changed .` → 5/222 file cần format: `lib/core/state/screen_state.dart`, `lib/features/academic/presentation/viewmodels/academic_page_view_model.dart`, `lib/features/account/presentation/viewmodels/notification_view_model.dart`, `test/behavior_preservation_visual_test.dart`, `test/empty_state_refactor_test.dart` | Có thể do khác phiên bản formatter (3.13.3 so với 3.13.4) → kiểm lại sau khi đồng bộ SDK |
| Không secret | **MỘT PHẦN** | Không có service-account, Cloudinary secret hay AWS key trong file tracked. `AIza...` chỉ ở `firebase_options.dart` (được phép). `server/.env` có nhiều `GOOGLE_API_KEY_*`, `GROQ_API_KEY`... nhưng **đã ignore** (`.gitignore:2`) và chưa từng commit. **Nhưng** `app/.dart_tool/chrome-device/Default/{Login Data, Network/Cookies, Secure Preferences,...}` **đã commit** (commit `57961a4`) | Xem vấn đề B1 |
| Xử lý lỗi mạng/permission/upload | THIẾU | Chỉ có lỗi nghiệp vụ `AcademicFailure` (`management_actions.dart`, `review_actions.dart`) | — |
| Async + loading | ĐỦ (mô hình) | `AsyncNotifier`/`ScreenState`; AI loading giả `review_actions.dart:349` | — |

### F. Kiểm thử MobAI

| Yêu cầu | Trạng thái | Ghi chú |
|---|---|---|
| `mobai_tests/` 10 file `.mob` | **THIẾU** | Không có file `.mob` nào. Có widget/integration test cũ (`mobile/test/`, `mobile/integration_test/`) nhưng không thay được |
| `docs/test-report.md` | **THIẾU** | `LAB3/PRM393_Lab03/docs/test-plan.md` viết cho **ARTEMIS** (`:3`), không phải MobAI |
| Healing + bug-catching exercise | **THIẾU** | Đề yêu cầu (spec trang 10, rubric 3+3 điểm); prompt của nhóm chưa liệt kê mục này |
| Key/Semantics ổn định | THIẾU | Chỉ 4 `ValueKey` có nghĩa và đều tạo động (`directory_screens.dart:147`, `academic_form_sheet.dart:96,269`, `dashboard_screen.dart:39`) |

### G. Quy trình và tài liệu

| Mục | Trạng thái | Bằng chứng |
|---|---|---|
| README.md | MỘT PHẦN | `mobile/README.md:1-50` mô tả Phase 1–4, nói "Không Firebase" (`:17`), "Chưa khởi tạo Git" (`:50`); thiếu link Figma, setup Firebase/Cloudinary |
| implementation-ai-log.md | THIẾU | — (chỉ có `AI-Review--ui/ai-design-log.md` của Lab 2) |
| code-review.md | THIẾU (template) | `LAB3/PRM393_Lab03/docs/code-review.md:9-13` toàn `[...]` |
| analytics-plan.md | MỘT PHẦN | `LAB3/PRM393_Lab03/docs/analytics-plan.md` (xem B7) |
| assets/ screenshot | THIẾU | `mobile/assets/` chỉ có `fixtures/ fonts/ icons/`; ảnh cũ nằm rải ở `mobile/docs/evidence/phase1/*.png` |
| Git: commit theo thời gian | **MỘT PHẦN** | Repo `srs-review-ai`: 288 commit / 22 ngày (09/09–29/10/2026), 10+ PR merge (`ee2579e` PR#11, ...) — nhưng do nhóm khác/dự án gốc. **`mobile/` chỉ có 1 commit** `f4211b6` (29/10, "split repo into desktop and mobile", 1938 file), chỉ nằm trên `feat/deployToVps` và `feat/mobile-integration`, **không có trên `main`** |
| Nhánh feature + PR merge cho Lab 3 | THIẾU | Chưa có PR nào liên quan Lab 3 mobile |
| Tên repo `PRM393_Lab03_<StudentID>` | THIẾU | Remote hiện là `github.com/LeHuyTuong/srs-review-ai` |

### 2.2 Firestore rules (bước 9) — `LAB3/PRM393_Lab03/firebase/firestore.rules`

Điểm tốt: không có `if true`; đã test 23/23 case bằng Rules Test API (`LAB3/PRM393_Lab03/evidence/rules-test.txt`).

Rủi ro và điểm lệch đề:

1. **Mô hình dữ liệu dùng chung, không theo user** (`projects/{id}`, `reviews/{id}` ở cấp gốc, dòng 25, 46). Đề yêu cầu "scoped to the signed-in user (vd `users/{uid}/items`)… read and write only their own data". Rubric trừ điểm khi "data not separated per user".
2. **Supervisor không tự tạo được hồ sơ**: `users/{uid}` chỉ cho tạo với `role == 'student'` (dòng 17), mà `hasRole('supervisor')` lại cần cho `projects` create (dòng 27). App mobile chỉ dành cho Supervisor nên sẽ bị chặn nếu không có admin set role thủ công.
3. Thiếu validate dữ liệu: không kiểm kiểu/độ dài trường (`name`, `url`), không kiểm `createdAt == request.time`; `reports` không kiểm `url` có thuộc Cloudinary hay không (dòng 53-56).
4. `documents` không có rule `delete` → mặc định từ chối (ổn), nhưng `update` cho cả member sửa document của supervisor (dòng 35).
5. `get()` lồng nhau (dòng 6, 9) tốn lượt đọc và có thể lỗi khi document không tồn tại.
6. Rules gắn với project `prm-srs-ai`, còn app dùng `srs-review-ai-ff68b` → **deploy sai project**.

### 2.3 Truy vết nguồn dữ liệu (bước 4)

- grep `package:http|dio|localhost|127.0.0.1|10.0.2.2|https?://|HttpClient` trong `mobile/lib` → chỉ 1 kết quả: chuỗi hiển thị link tham gia `features/academic/presentation/views/widgets/student_enrollment_sheet.dart:96` (`https://review.university.edu.vn/join/...`), không phải lời gọi mạng.
- **Kết luận: app mobile KHÔNG phụ thuộc server Python.** Nguồn dữ liệu:
  - `assets/fixtures/academic.json` → `FakeAcademicService` (`fake_academic_service.dart:21`), giữ trong RAM, mất khi khởi động lại.
  - `assets/fixtures/dashboard.json` → `FakeDashboardService` (thực tế lấy `dashboardJson` từ academic, `core/di/data_providers.dart:28-34`).
  - `assets/fixtures/notifications.json` → `NotificationService` (`notification_service.dart:10`).
- Server Python chỉ được dùng bởi `desktop/` (`desktop/lib/core/app_config.dart:20-30`).

---

## 3. Danh sách vấn đề

### 3.1 Chặn nộp bài

| ID | Vấn đề | File | Cách sửa đề xuất | Độ khó |
|---|---|---|---|---|
| B1 | Hồ sơ Chrome (Cookies, Login Data, Secure Preferences) đã commit | `app/.dart_tool/chrome-device/**` (commit `57961a4`) | Không đưa thư mục này vào repo nộp bài. Repo mới (B3) chỉ chứa `mobile/`. Repo cũ: `git rm -r --cached app/` và thêm vào `.gitignore`. Vì đã lên GitHub, coi như lộ: đăng xuất mọi phiên Google trên profile đó, đổi mật khẩu tài khoản đã dùng | S |
| B2 | Dart SDK 3.13.3 < `sdk: ^3.13.4`, nên `pub get`/`analyze` lỗi | `mobile/pubspec.yaml:22` | `flutter upgrade` lên bản có Dart ≥3.13.4 (README ghi 3.47.5), hoặc hạ ràng buộc xuống `^3.13.3`. Ghim `firebase_core` thay vì `any` (`:43`) | S |
| B3 | Không có repo `PRM393_Lab03_<StudentID>`; mobile chỉ có 1 commit, không trên `main`, không PR | git | Tạo repo mới, root = nội dung `mobile/` + `firebase/` + `docs/`. Commit theo từng nhiệm vụ, mỗi giai đoạn một nhánh `feat/*`, ≥1 PR merge vào `main` | M |
| B4 | Không có Google Sign-In; login mô phỏng có mật khẩu điền sẵn | `session_view_model.dart:37-51`, `login_screen.dart:25-26,93-96`, `google-services.json:15` | Thêm `firebase_auth` + `google_sign_in`; `AuthService`; đăng ký SHA-1; tải lại `google-services.json` | M |
| B5 | Không có Firestore; mọi CRUD và flow chạy trên fixture | `core/di/data_providers.dart:41-54`, `fake_academic_service.dart` | `FirestoreService` + repository thật, thay provider bằng override; listener `snapshots()` cho danh sách Project/Review; nút seed | L |
| B6 | Flow F3 (Student) không tồn tại; app chặn vai trò khác Supervisor | `session_view_model.dart:38-40`; Lab 2 `AI-Review--ui/ux/user-flow.md:148-170` | **Cần hỏi giảng viên** (mục 7). Phương án A: thêm 4–6 màn Student, vai trò lưu trong `users/{uid}`. Phương án B: ghi `design-change-log.md` thu F3 thành luồng Supervisor (nhận bản nộp lại v2 rồi duyệt) | L / M |
| B7 | Chưa có 6 dịch vụ Firebase + PDF/Cloudinary | `pubspec.yaml:30-43`, `AndroidManifest.xml`, `build.gradle.kts` | Xem kế hoạch mục 5 | L |
| B8 | Rules không owner-only, lệch project | `LAB3/PRM393_Lab03/firebase/firestore.rules`, `.firebaserc:3` vs `mobile/firebase.json:6` | Viết lại theo `match /users/{uid}/{doc=**} { allow read, write: if request.auth.uid == uid && <validate>; }`; chọn **một** project; deploy lại | M |
| B9 | Không có `mobai_tests/` và các docs bắt buộc | — | Mục 5, 6 | L |

### 3.2 Mất điểm lớn

| ID | Vấn đề | File | Cách sửa | Độ khó |
|---|---|---|---|---|
| L1 | Nhánh lỗi AI không kích hoạt được từ UI | `review_panel_view_model.dart:69`, `review_actions.dart:278,360` | Lỗi phải do sự kiện thật: ghi Firestore thất bại khi offline, hoặc Remote Config `ai_review_enabled=false` → thông báo + Thử lại. Không giữ cờ `simulateError` | M |
| L2 | `mobile/firebase.json:25-41` khai báo Cloud Functions | `mobile/firebase.json` | Xóa khối `functions` (ràng buộc Spark) | S |
| L3 | Profile không có ảnh/tên/email từ Google, không có giá trị Remote Config, không có nút Crashlytics | `account_screens.dart:7-126` | Lấy từ `AuthService.currentUser`; thêm khu "Demo" với 2 giá trị RC + 2 nút | S |
| L4 | Analytics plan thiếu `screen_view`, `export_pdf`; có `project_name` | `LAB3/.../analytics-plan.md:10,19` | Sửa plan; thêm `NavigatorObserver` của FirebaseAnalytics | S |
| L5 | `lib/screens/`, `viewmodels/`... chỉ là shim; thiếu `utils/` | `lib/screens/**` | Chuyển code thật về cấu trúc mục 5 của đề, hoặc giữ `features/` và giải thích trong README + report (rủi ro bị hỏi khi vấn đáp) | M |
| L6 | Model là một snapshot JSON lớn, khó map sang Firestore | `core/domain/academic/academic_models.dart`, `fake_academic_service.dart:40-71` | Tách model Project/Review/Notification/Report có `fromMap/toMap`; repository theo collection | L |
| L7 | Test plan và code-review viết cho ARTEMIS, yêu cầu ≥5 findings (bản đề khác) | `LAB3/.../test-plan.md:3`, `code-review.md:5` | Đồng bộ theo bản MobAI (≥3 findings, 10 `.mob`) sau khi hỏi thầy | S |
| L8 | Không có Key/Semantics ổn định cho test | toàn `lib/` | Thêm `Semantics(identifier: ...)` hoặc `Key` cho các phần tử ở mục 6 | M |
| L9 | Thiếu healing + bug-catching exercise (6 điểm) | — | Lên lịch sau khi 10 test pass | S |

### 3.3 Mất điểm nhỏ

| ID | Vấn đề | File | Cách sửa | Độ khó |
|---|---|---|---|---|
| N1 | 5 file chưa `dart format` | liệt kê ở E | `dart format .` sau khi đồng bộ SDK | S |
| N2 | Hard-code ngoài theme | `sample_document_reader.dart:362,373,401,405`; `app_academic_layout.dart:83` | Đưa vào `AppRadius.chip`, `AppMetrics`; hoặc ghi ngoại lệ có lý do trong fidelity-check | S |
| N3 | Màn Demo counter + `counter_*` còn trong app | `features/demo/**`, `core/di/data_providers.dart:19-26` | Xóa | S |
| N4 | `applicationId = com.example.srs_review_ai_mobile` | `build.gradle.kts:22` | Đổi trước khi đăng ký SHA-1 và tải `google-services.json` (nếu đổi sau thì phải đăng ký lại) | S |
| N5 | README lỗi thời | `mobile/README.md:3-50` | Viết lại theo 12.1 | S |
| N6 | Logic trình bày đọc trực tiếp `data['currentUser']` trong View | `account_screens.dart:13-15` | Đưa vào ProfileViewModel | S |

---

## 4. Quyết định về server Python

**Quyết định: BỎ khỏi bài nộp Lab 3.** App mobile không gọi endpoint nào (mục 2.3), và đề cấm "custom backend servers" (spec trang 2, "Out of scope"). Server vẫn phục vụ `desktop/` nên giữ nguyên trong repo `srs-review-ai`, chỉ không đưa vào repo `PRM393_Lab03_<ID>`.

Chức năng mà mobile đang mô phỏng và endpoint tương ứng của server, kèm phương án thay thế bằng Firestore. Thứ tự là thứ tự nên làm:

| Thứ tự | Chức năng mobile (đang giả) | Endpoint server tương đương | Thay bằng |
|---|---|---|---|
| 1 | Hồ sơ người dùng | (không có) | `users/{uid}` (displayName, photoUrl, role, fcmToken) |
| 2 | **Project (entity chính)** CRUD | — | `users/{uid}/projects/{projectId}` + listener |
| 3 | Học vụ (semester/course/class/group/student/ruleSet) | `POST/GET/PATCH/DELETE /classes` (`server/app/api/classes.py:91-186`) | `users/{uid}/catalog/{kind}` hoặc subcollection riêng; seed từ `academic.json` |
| 4 | Review + quyết định | `/submissions/*`, `/submissions/{id}/decision` (`submissions.py:101-236`) | `users/{uid}/reviews/{reviewId}` + subcollection `versions`, `feedback`, `history` |
| 5 | Kết quả AI | `POST /review`, `/review/batch` (`review.py:42,117`) | Giữ AI **mô phỏng tất định** nhưng lưu vào `users/{uid}/reviews/{id}/evaluations`. Ghi trong design-change-log lý do (không có backend, không đưa LLM key vào app). Gọi LLM thật qua Firebase AI Logic là tùy chọn, **chưa xác minh** điều kiện gói Spark |
| 6 | Thông báo | — | `users/{uid}/notifications` (ghi khi nhận FCM hoặc khi đổi trạng thái review) |
| 7 | Báo cáo PDF | `/submissions/{id}/report` (`submissions.py:279`), `/uploads/presign`, `PUT /uploads/{key}` (`uploads.py:43-91`) | Upload thẳng Cloudinary bằng unsigned preset; metadata ở `users/{uid}/reports/{reportId}` |
| — | `/ask`, `/diagram`, `/health` | `ask.py:22`, `diagram.py:70`, `health.py:23` | Bỏ |

---

## 5. Kế hoạch thực hiện

Mỗi ô ≈ 1 buổi (3–4 giờ). Ký hiệu ∥ = làm song song được nếu có nhiều người.

### 5.1 Đọc spec
- [ ] **T1** Chốt các câu hỏi ở mục 7 với giảng viên (MobAI hay ARTEMIS, F3, Cloudinary). Chốt entity chính = Project.

### 5.2 Setup
- [ ] **T2** Đồng bộ Flutter/Dart (B2), chạy `flutter pub get`, `flutter analyze` sạch, `dart format`. Đổi `applicationId` (N4). Tạo repo `PRM393_Lab03_<ID>` từ `mobile/`, bỏ `app/` (B1, B3), nhánh `feat/setup`.
- [ ] **T3** ∥ Người dùng làm thủ công trên console (mục 8). Chọn **một** Firebase project. `flutterfire configure` lại để `google-services.json` có `oauth_client`.
- [ ] **T4** ∥ Viết `docs/handoff-gaps.md` và `docs/design-change-log.md` (nguồn: `mobile/docs/design-traceability.md`, `phase*-ui-report.md`). Bắt đầu `docs/implementation-ai-log.md`.

### 5.3 Build (kiến trúc)
- [ ] **T5** Tách model Project/Review/Notification/Report (`fromMap/toMap`). Tạo interface `AuthService`, `FirestoreService`, `FileStorageService`, `AnalyticsService`, `CrashService`, `RemoteConfigService`, `MessagingService` trong `lib/services/`. Dọn shim và demo counter (L5, L6, N3).

### 5.4 Connect (Firebase)
- [ ] **T6** Auth Google + Profile thật + guard + sign out (B4, L3).
- [ ] **T7** Firestore: repository Project có CRUD, `orderBy`/`where`, `snapshots()`; nút "Tạo dữ liệu mẫu"; rules owner-only + deploy (B5, B8).
- [ ] **T8** Firestore cho Review (F2) và học vụ (F1). Bắt lỗi mạng/permission → error state thật (L1).
- [ ] **T9** ∥ Remote Config (`ai_review_enabled`, `review_queue_page_size`) + Crashlytics (plugin gradle, `setUserIdentifier`, custom key `role`/`screen`, 2 nút demo).
- [ ] **T10** ∥ Analytics: sửa plan (L4), `AnalyticsService`, `NavigatorObserver`, các event `view_project`, `create_/update_/delete_project`, `export_pdf`, `run_ai_review`, `submit_review_decision`.
- [ ] **T11** ∥ FCM: `POST_NOTIFICATIONS`, xin quyền, `flutter_local_notifications` cho foreground, background handler, `onMessageOpenedApp`/`getInitialMessage` → route trong `data.route`; ghi vào `users/{uid}/notifications`.
- [ ] **T12** ∥ PDF: package `pdf` dùng font Inter + màu `AppColors`; upload Cloudinary (`http` multipart, preset unsigned); lưu `reports`; nút mở bằng `url_launcher`; xử lý lỗi upload.
- [ ] **T13** F3 theo quyết định ở T1 (phương án A: màn Student; phương án B: design-change-log + luồng Supervisor).

### 5.5 Test
- [ ] **T14** Thêm `Semantics(identifier:)`/`Key` (mục 6). Tạo tài khoản Google test. Ghi lại clean state.
- [ ] **T15** Viết 10 `.mob` + `docs/test-report.md`; chạy ≥1 lượt đầy đủ, lưu log và ảnh.
- [ ] **T16** Healing exercise + bug-catching exercise.

### 5.6 Review
- [ ] **T17** Mở PR `feat/* → main`, chạy AI review (CodeRabbit/Copilot), ≥3 findings (≥1 về security), sửa và ghi `docs/code-review.md`, kèm review rules.

### 5.7 Verify
- [ ] **T18** `flutter analyze` 0 error, `dart format` sạch, quét secret, chạy lại 10 test, `docs/fidelity-check.md` (360×800, 412 dp, contrast, 48 dp, airplane mode cho error state), chụp DebugView/Crashlytics/Firestore.

### 5.8 Document
- [ ] **T19** README đầy đủ, `assets/` ảnh, report 5–10 trang, video 3–5 phút, kiểm repo mở được ở cửa sổ ẩn danh.

**Song song tối đa:** sau T5–T6, có thể chia T9, T10, T11, T12 cho 4 người. T4 làm song song từ đầu.

---

## 6. Kế hoạch test 10 kịch bản MobAI

Clean state chung: cài lại app (xóa dữ liệu), tài khoản Google test `<test-account>` (không commit thông tin đăng nhập), Firestore của uid test đã reset bằng nút "Tạo dữ liệu mẫu" trong Profile → Demo. Seed tối thiểu: 1 học kỳ đang hoạt động, 1 course offering, 1 lớp, 2 nhóm (G1 chưa có dự án, G2 đã có dự án P2), 1 review `R1` trạng thái "Chờ đánh giá" có rule set bật AI.

Hiện **không có Key cố định nào** dùng được; cột (d) ghi label hiện có và **Key/identifier cần thêm** (đánh dấu ➕).

| # | (a) Điều kiện đầu + seed | (b) Bước | (c) Assert nhìn thấy | (d) Neo trong code |
|---|---|---|---|---|
| 1 Sign-In | Chưa đăng nhập, app mới cài | Mở app → chạm "Đăng nhập với Google" → chọn tài khoản test (bước chọn tài khoản có thể phải làm tay, cần ghi lý do) | Màn Tổng quan hiện; header/Profile có **tên hiển thị của tài khoản test** | Hiện tại là nút "Đăng nhập" `login_screen.dart:84`. ➕ `login.google`, ➕ `dashboard.greeting` |
| 2 F1 happy | Đăng nhập; seed có G1 chưa có dự án | Tab Tài khoản → "Lớp học" → lớp → G1 → "Tạo dự án" → nhập tên `Dự án MobAI` → Lưu | Group detail hiện `Dự án MobAI`; mở Project Detail thấy tên + "Lab kế thừa" | `account_screens.dart:89` ("Lớp học"), `group_screens.dart:215` ("Tạo dự án"). ➕ `project.form.name`, `project.form.save`, `group.project.title`, `project.detail.title` |
| 3 F2 happy | R1 chờ đánh giá; RC `ai_review_enabled=true` | Tab "Đánh giá" → R1 → "Bắt đầu đánh giá" → chạy AI → chờ kết quả → "Phê duyệt" → xác nhận | Badge trạng thái **"Đã phê duyệt"**; Lịch sử quyết định có dòng mới | `app_bottom_navigation.dart:22`, `review_screens.dart:282,304,212`. ➕ `review.item.R1`, `review.ai.run`, `review.ai.result`, `review.approve`, `dialog.confirm`, `review.status` |
| 4 F3 happy | **Bị chặn bởi B6.** Phương án A: tài khoản Student test + tài liệu "Cần chỉnh sửa" | (A) Student tải v2 → nộp → Supervisor duyệt → Student mở lịch sử phiên bản | "2 phiên bản", trạng thái "Đã phê duyệt" | Chưa có màn → ➕ toàn bộ |
| 5 Lỗi/recovery | Đề xuất 2 nhánh có thật: (i) F1 bỏ trống tên; (ii) bật airplane mode khi chạy AI hoặc lưu quyết định | (i) Tạo dự án, xóa tên → Lưu → nhập lại → Lưu. (ii) Bật airplane → thao tác → thấy lỗi → tắt airplane → "Thử lại" | (i) Thông báo "Nhập tên và khoảng thời gian dự án hợp lệ." (`management_actions.dart:166`), sau đó dự án xuất hiện. (ii) Text lỗi mạng, sau đó trạng thái thành công | `ai_review_panel.dart:295` ("Thử lại Đánh giá AI"). ➕ `form.error`, `error.retry`. **Cần sửa L1 trước** |
| 6 CRUD Project | Có dự án `P-test` | Tạo `P-test` → mở detail → "Chỉnh sửa thông tin" đổi tên `P-test-2` → quay lại list → "Xóa dự án" → xác nhận | List và detail hiện `P-test-2`; sau khi xóa, list **không còn** `P-test-2` | `project_screens.dart:21,337,160`. ➕ `project.list.item.<id>`, `project.menu`, `project.delete` |
| 7 Điều hướng | Đăng nhập, seed đủ | Lần lượt 5 tab: Tổng quan, Dự án, Đánh giá, Thông báo, Tài khoản; mỗi tab Back về | Mỗi tab có tiêu đề đúng và ít nhất 1 item (hoặc empty state đúng chữ) | `app_bottom_navigation.dart:20-24`. ➕ `nav.<path>`, `page.title` |
| 8 Profile + RC | Console đã publish 2 giá trị khác default | Mở Tài khoản → cuộn tới "Demo" | Ảnh, tên, email Google; **2 giá trị RC đúng với console**; tác động thật (vd queue chỉ hiện N item) | ➕ `profile.name`, `profile.email`, `profile.rc.ai_review_enabled`, `profile.rc.review_queue_page_size` |
| 9 PDF export | Có ≥1 dự án; có mạng | Project Detail (hoặc Profile) → "Xuất PDF" → chờ | Chữ "Đã tải lên" + URL `https://res.cloudinary.com/...` hoặc nút "Mở PDF" hiện | ➕ `pdf.export`, `pdf.progress`, `pdf.url`, `pdf.open` |
| 10 Sign out | Đăng nhập | Tài khoản → "Đăng xuất" | Màn Login hiện; mở lại app vẫn ở Login | `account_screens.dart:117-122`. ➕ `profile.signout`, `login.google` |

Ghi chú kỹ thuật cho test ổn định:

- Trên Android, `Semantics(identifier: 'x')` được xuất thành resource-id cho công cụ dựa trên accessibility tree. Nên dùng cách này thay vì dựa vào chữ tiếng Việt, vì chữ sẽ bị đổi trong healing exercise. MobAI có đọc được resource-id hay không thì **chưa xác minh**; cần thử ở T14.
- Animation AI giả 1200 ms (`review_actions.dart:349`) → script phải dùng `wait for` theo text kết quả, không dùng sleep cố định.

---

## 7. Các điểm cần hỏi lại giảng viên

1. **Hai bản đề Lab 3 mâu thuẫn:** `PRM393 - Lab 3 From Design to Working App…pdf` (MobAI, Cloudinary được khuyến nghị, ≥3 findings, 10 `.mob`, 17 trang) và `PRM393 - Lab 3 Cloud-Enabled Mobile App (Firebase, Patrol, AI Code Review).pdf` (ARTEMIS/pytest, Cloud Storage + `storage.rules`, ≥7 event, 18 trang). Chấm theo bản nào? Khung `LAB3/PRM393_Lab03/` đang theo bản ARTEMIS.
2. Số event Analytics: bảng cố định (login, logout, screen_view, view/create/update/delete, export_pdf + ≥2) hay "ít nhất 7 event"?
3. Số findings code review: 3 (bản MobAI) hay 5 (`LAB3/.../code-review.md:5`)? Có cần mỗi fix một commit không?
4. Độ dài báo cáo (5–10 trang) và video (3–5 phút) — có giữ nguyên không?
5. Làm **cá nhân** ("Individual unless the lecturer announces teams") hay nhóm? Nếu cá nhân thì mỗi người một Firebase project và một repo?
6. App mobile là **Supervisor-only**. F3 của Lab 2 cần vai trò Student: phải làm màn Student, hay được ghi design-change-log để thu gọn?
7. Mô hình dữ liệu nhiều vai trò (Supervisor đọc bài nộp của Student) có được chấp nhận thay cho "chỉ owner đọc/ghi" không?
8. Có được giữ server Python trong repo (không dùng) không, hay phải tách hẳn?
9. Tính năng "Đánh giá AI" để mô phỏng (không có backend) có bị coi là "fake data" không?
10. Số commit và số ngày tối thiểu (`[N]` trong đề, trang 16, chưa điền)? Trọng số Lab 3 trong điểm môn (trang 1 để trống)?
11. Có chấp nhận lịch sử commit mới bắt đầu từ repo `PRM393_Lab03_<ID>` (code UI đã làm trước đó ở repo khác) không?

---

## 8. Việc người dùng phải tự làm trên console

Dùng tài khoản `hienngunguoi1234@gmail.com`, **chỉ gói Spark**, không gắn billing.

1. Chọn **một** Firebase project (`srs-review-ai-ff68b` hoặc `prm-srs-ai`; cần kiểm cái nào thuộc tài khoản trên bằng `firebase projects:list`). Bật Google Analytics cho project.
2. Authentication → Sign-in method → bật **Google**, đặt support email.
3. Lấy SHA-1 debug: `cd android && ./gradlew signingReport` (hoặc `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android`). Thêm SHA-1 (và SHA-256) vào Project settings → Android app (đúng `applicationId` mới). Tải lại `google-services.json` và kiểm `oauth_client` không rỗng.
4. Firestore → Create database (production mode, region gần, vd `asia-southeast1`). Deploy rules: `firebase deploy --only firestore:rules --project <id>`.
5. Cloud Messaging: không cần bật thêm. Gửi thử từ Messaging → "New campaign → Notifications", thêm custom data `route=/reviews/R1`.
6. Remote Config: tạo 2 tham số `ai_review_enabled` (bool), `review_queue_page_size` (number), rồi Publish.
7. Crashlytics: mở trang Crashlytics, bấm "Enable". Chạy app bản debug một lần để dashboard nhận.
8. Analytics DebugView: `adb shell setprop debug.firebase.analytics.app <applicationId>`.
9. Cloudinary (gói Free): Settings → Upload → Upload presets → Add → **Unsigned**, folder `prm393/reports`, Allowed formats `pdf`, Max file size (vd 5 MB), resource type `raw` hoặc `auto` (cần thử xem PDF có mở được không). Chỉ đưa `cloud_name` + `upload_preset` vào app (qua `--dart-define`), **không** đưa API secret.
10. Tạo **tài khoản Google riêng để test** MobAI; đăng nhập sẵn tài khoản này vào emulator có Google Play.
11. Cài MobAI desktop + emulator Android có Google Play (API 33+ để test quyền `POST_NOTIFICATIONS`).
12. GitHub: tạo repo `PRM393_Lab03_<StudentID>` (public hoặc mời giảng viên), cài CodeRabbit/Copilot review cho repo.
13. Vì hồ sơ Chrome đã bị commit (B1): đăng xuất phiên trên các tài khoản đã dùng trong profile `chrome-device` và đổi mật khẩu.
