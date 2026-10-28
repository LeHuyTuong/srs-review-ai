# Giải quyết từng issue

26/10/2026. FIXED dưới đây chỉ áp dụng phạm vi issue được audit, không là chứng nhận mọi nhánh backend/accessibility/MVVM của sản phẩm. Không sửa React và không mở rộng Student Mobile.

## AUD-U01 — FIXED

- **Root cause/before:** key `'$kind-${state.q.isEmpty}'` thay đổi khi nhập ký tự đầu, hủy TextFormField đang focus.
- **Files:** `lib/widgets/app_search_field.dart`; `lib/screens/management/widgets/management_filter_bar.dart`; `lib/screens/academic/widgets/class_filter_bar.dart`.
- **After:** controller sống cùng StatefulWidget; key theo kind ổn định. Input do người dùng cập nhật không bị viết lại controller/caret/composing. Chỉ external clear/restore thay giá trị khi khác. Controller dispose theo widget. Không requestFocus liên tục.
- **Tests added:** năm widget regression `/projects`, `/reviews`, `/documents`, `/classes`, `/students`: cập nhật từng ký tự bằng test keyboard, focus identity, keyboard visible, caret giữa chuỗi, filter, clear, Back/dispose. PASS trong full suite.
- **Android:** bấm trực tiếp từng phím Gboard `s→m→a→r→t`, không refocus, kết quả 2 dự án; bàn phím giữ mở. Clear trả danh sách và query trống khi IME vẫn mở. `390-search-smart-gboard.png`, `390-search-cleared-ime.png`, `native-ime.log`.
- **Remaining:** Course list không có search để sửa; không thêm mới. Native không lặp mọi màn dùng component; test bao phủ năm route. Không đo mọi keyboard/composition ngôn ngữ.

## AUD-A02 — FIXED trong lifecycle client mock; authorization thật còn chờ Firebase

- **Root cause/before:** chỉ gán session=null, root providers và saved state vẫn sống; email không thành identity; không có token chống tác vụ cũ.
- **Files:** `lib/app/session.dart`, `app.dart`, `providers.dart`; `lib/models/session_scope.dart`; scoped fake repository/service; notifications repository; các VM academic/dashboard/filter/form/reader/AI/enrollment được ghi trong `source-changes.json`.
- **After:** identity mock `mock:<normalized email>` + generation; SessionScope có revoke đồng bộ. Notifier session sở hữu scope, provider chỉ công bố scope, tránh provider phụ thuộc vòng vào chính session. App navigator key theo session, nên route stack cũ bị hủy. Dependent VM state rebuild, saved maps clear. Repository cũ từ chối load/write; service kiểm tra scope **sau await và trước atomic publish**. AI run, form, file picker, enrollment/feedback callbacks giữ scope gốc, bỏ kết quả trễ.
- **Shared-data decision:** FakeAcademicService giữ **committed domain aggregate dùng chung** như server fake. Không xóa Course/Project hợp lệ lúc logout. Repository handle/VM caches/filter/draft là client state theo phiên. Shared config/gateway không bị reset nhầm. Không sửa JSON fixture.
- **Tests added:** logout→login, A→B, same-user generation mới, repository replacement, retained shared committed Course, filters/saved views reset, old repository denied, late fake commit, late AI completion, protected navigation/Back. PASS. Test picker/form hiện có cùng full suite tiếp tục PASS.
- **Android:** A query `P45`/All-semester→logout→login `b@example.test`→Projects trở về query trống/Fall2026/active default; 13 active projects vẫn còn đúng shared-store lifecycle. Logout B→Android Back ra launcher→mở lại chỉ Login. Checkpoints `390-login-identity-b.png`, `390-session-b-cleared-search-shared-data.png`, `390-logout-back-launcher.png`, `390-reopen-signed-out.png`.
- **Remaining:** chưa xác thực Google/UID/ownership; actor/Profile vẫn mẫu chung. Hủy operation đã có commit chuẩn bị AI không xóa lịch sử hợp lệ đã commit; loading AI gián đoạn có thể retry trong cơ chế hiện có. Không tuyên bố client token thay server authorization. Direct unscoped fake constructors dùng cho test không là production security boundary.

## AUD-B03 — FIXED

- **Root cause/before:** code khác nhau `AUDIT A` / `AUDIT-A` tạo cùng slug ID và upsert ghi đè; uniqueness chỉ theo code chính xác tại VM.
- **Files:** `academic_view_model.dart`, `repositories/academic/course_contract.dart`, fake academic repository/service; hai test academic cũ được cập nhật ID lookup.
- **After:** Course mới dùng `nextId('course')`, không migrate ID fixture cũ. Typed mutation phân biệt create/update; create đụng ID bị reject, edit ID không tồn tại bị reject. Mã uppercase/trim, duplicate code kiểm tra trước ghi và tại commit. Update giữ ID và unknown fields; các edges Offering/Class/Rule không đổi. Atomic revision guard ngăn lost update.
- **Tests added:** normalized-slug collision giữ cả hai Course; duplicate create/edit, unknown edit ID không đổi snapshot; stable ID sau đổi code; commit duplicate ID/code; stale revision; insertion ID collision; concurrent same-code commands chỉ một thành công; unknown fields và references/history giữ nguyên. PASS.
- **Android:** nhập SWP391+name→Save hiện “Mã môn đã tồn tại”, form không đóng. Đổi thành SWP391P45→save hợp lệ, Profile đếm môn 4→5. `390-course-duplicate-blocked.png`. Slug collision/concurrency được kiểm chứng tự động, không gán là thử native.
- **Remaining:** ID generator local là mock; khi dùng backend phải dùng server/Firestore IDs và unique-code index/transaction. Test cũ tra slug được đổi sang tìm Course theo code, sau đó kiểm tra qua ID đã lưu; không bỏ assertion nghiệp vụ.

## AUD-B02 — FIXED

- **Root cause/before:** management queries có Class fallback sau detach; Dashboard chỉ map groupId nên mất Project khỏi thống kê.
- **Files:** `models/academic/project_context.dart`, `management_queries.dart`, `models/dashboard/dashboard_snapshot.dart`, `viewmodels/dashboard/dashboard_view_model.dart`.
- **After:** một resolver dùng chung: Group.classId khi có group, nếu detach dùng Project.classId. Dashboard DTO mang classId; cùng policy với Project list. Không tạo lại group hoặc sửa review history.
- **Tests added:** tạo group/project, xóa group rỗng hợp lệ, list/Class queries vẫn có Project, active count Dashboard không giảm, reviewState giữ nguyên. PASS.
- **Android:** SE1701→tạo Group09 rỗng→Project “P45 Detached”→xóa Group09 được phép→Class trở về 8 nhóm. Project list tìm P45 còn SE1701, group “—”; Dashboard Fall2026/Truy cập nhanh hiển thị **Đang thực hiện 13**, đúng list. `390-group-project-before-detach.png`, `390-detached-project-list.png`, `390-dashboard-detached-count-13.png`.
- **Remaining:** không sửa policy cho trường hợp dữ liệu backend thật có cả class/group references sai; server invariant/repair strategy cần phase migration. Không gọi orphan sai là hợp lệ.

## AUD-B01 — FIXED

- **Root cause/before:** invalidation sau mutation tải lại Dashboard và chọn học kỳ đầu, làm mất lựa chọn.
- **Files:** `dashboard_view_model.dart`, `dashboard_snapshot.dart`; scope/session lifecycle ở trên.
- **After:** selection là state riêng theo scope, giữ qua rebuild/retry. All-semester `''` được giữ có chủ ý. Khi học kỳ không còn trong tập hợp hợp lệ (xóa/archive), fallback sang lựa chọn đầu còn hợp lệ, nếu không có thì All. Session khác khởi tạo mới. ID lạ không được chọn.
- **Tests added:** Group/Project/Class mutations, retry, archive/restore/delete học kỳ trống, All-selection, logout→identity mới. PASS.
- **Android:** chọn Spring2027→đi Course, duplicate thất bại rồi save mã hợp lệ→Dashboard vẫn Spring2027; tiếp tục tạo/xóa Group/Project rồi về vẫn Spring2027, trước khi chủ động đổi Fall2026 để đọc counts. `390-semester-before.png`, `390-semester-after-mutation.png`.
- **Remaining:** fallback dựa danh sách trả về, không hardcode Fall2026. UX archived semester history của module Academic không bị xóa; chỉ loại khỏi selector Dashboard.

## AUD-A01 — FIXED các vị trí được chỉ ra; không blanket strict-MVVM PASS

- **Root cause/before:** builder chứa semester ranking/sort, grouped count, project-document tab filter/priority sort/count và rule criterion total.
- **Files:** `models/academic/academic_projections.dart`; VM directory/management-list/academic-form; Views directory/document/form-sheet.
- **After:** pure projection/VM expose orderedSemesters, groupedCount, ProjectDocumentProjection counts/visible, criterionTotal. View render và gửi action; layout/date formatting vẫn ở View. Group count giữ đúng membership semantics cũ, không dùng nhầm field groupId của student.
- **Tests added:** phase/date ordering/tie-break, membership dedupe trong visible set, document statuses/priority/order/tab counts và input immutability, enabled criterion total/numeric draft. PASS; existing widget suite PASS.
- **Android:** đường Course/Group/Project/Dashboard sau refactor hoạt động; không lặp native mọi Rule/Document tab, dựa targeted/existing widget tests cho các phần đó.
- **Remaining:** scope theo audit, không quét-refactor toàn bộ UI. Những relationship/count projection legacy khác trong màn Academic vẫn còn; không tuyên bố toàn bộ build của app không có nghiệp vụ. Dependency check: không tạo SCC import mới, không VM import screens/widgets.

## AUD-A03 — PARTIAL / migration có kiểm soát

- **Root cause/before:** toàn aggregate load/commit, raw casts, chưa có identity/ownership hoặc backend transaction contract.
- **Files:** `course_contract.dart`; fake repository/service; VM academic; error enum trong `academic_models.dart`; session scope.
- **After:** CourseDto kiểm tra primitive/required fields và freeze/preserve unknowns; codec kiểm tra root/courses tại asset edge; typed CourseMutation create/update áp dụng lại trên current snapshot ở data boundary. CourseCommandRepository additive được VM dùng khi adapter hỗ trợ; legacy repository test/Phase1–4 vẫn tương thích. Error codes validation/conflict/sessionExpired/invalidData/permissionDenied/notFound được khai báo; các lỗi mới dùng code tương ứng.
- **Tests added:** DTO malformed/unknown fields/deep copy; typed insert collision; concurrent same-code commands; actual VM→fake typed seam; legacy workflows qua full suite. PASS.
- **Android:** Course create/duplicate dùng adapter mặc định/typed seam thật; không có Firestore hoặc server permissions để test.
- **Remaining:** chưa chia tất cả entity DTO/query/subscription/commands; load/commit snapshot còn cho workflow khác và return value tương thích. Chưa triển khai ownership ACL hoặc multi-user/offline Firestore semantics. [Kế hoạch migration](architecture-changes.md) ghi rõ các bước, không gọi adapter hiện tại là drop-in Firebase.
