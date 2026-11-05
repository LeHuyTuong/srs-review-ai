# Checklist hoàn thiện Lab 3 theo PDF và chỉ dẫn bổ sung của giảng viên

Ngày lập: 05/11/2026. Đây là tiêu chí cần đạt, không phải kết quả kiểm thử hoặc cam kết đã triển khai.

Nguồn:

- L: `F:/study/PRM/LAB3/PRM393 - Lab 3 From Design to Working App with Flutter and Firebase.pdf`, 17 trang.
- P: `F:/study/PRM/LAB3/PRM393_Lab3_Preparation_Guide_v5_ToiUu.pdf`, 25 trang.
- T: lời giảng viên được người dùng cung cấp trong hội thoại ngày 05/11: cho phép Cloudinary hoặc S3 thay storage; chấm trên device thật; nút crash thật; Dev xem Firebase, Admin dùng web; web chỉ phục vụ Admin; ưu tiên công nghệ và giải thích bằng slide, gồm luồng FCM từ token đến server và client.

T cập nhật các điểm tương ứng trong PDF. Chọn Cloudinary cho checklist này. Không còn yêu cầu bắt buộc Firebase Storage hoặc `storage.rules` của Firebase cho file Cloudinary. Yêu cầu bảo vệ Firestore vẫn giữ nguyên.

Đối chiếu source đã thực hiện riêng tại [báo cáo hiện trạng](lab3-review-2026-11-05.md). Không diễn giải checklist dưới đây là code hiện tại đã đạt.

## 1. App trên thiết bị thật

- [ ] Sửa parse error của `mobile/lib/main.dart`, khai báo dependencies đúng và rà cấu hình Gradle.
- [ ] `dart format`, `flutter analyze`, unit/widget tests phù hợp hoàn tất; lưu output của đúng phiên bản nộp.
- [ ] Build, cài và chạy trên điện thoại Android thật. Ghi model máy, Android version, app version và commit.
- [ ] Google Sign-In hoạt động với cấu hình ký của bản đem chấm; chuẩn bị tài khoản kiểm thử riêng.
- [ ] App khởi động, đóng/mở lại và logout không để lộ màn hình hoặc dữ liệu ngoài quyền.
- [ ] Có trạng thái loading, empty, data, error và thao tác thử lại phù hợp.
- [ ] Toàn bộ màn Lab 2, tối thiểu tám màn, navigation và Back hoạt động. Login/Profile được bổ sung nếu cần.
- [ ] Ba flow Lab 2 chạy trên dữ liệu thật, gồm nhánh lỗi và phục hồi. Ghi rõ thiết bị/client của từng bước. Lời thầy chỉ yêu cầu web Admin không tự miễn bước Student của flow cũ; nếu thay flow thì cập nhật thiết kế và log thay đổi.

Nguồn: L tr.2–5,8,13; T về thiết bị thật và web Admin.

## 2. MVVM, Firestore và quyền truy cập

- [ ] View render state và chuyển sự kiện; ViewModel xử lý trạng thái/nghiệp vụ; Service gọi SDK/API. Riverpod được dùng nhất quán.
- [ ] Có sơ đồ tầng, sequence diagram một flow đầy đủ, bảng ViewModel/Service và model chuyển đổi Firestore.
- [ ] Dữ liệu nghiệp vụ chính chuyển khỏi fixture/RAM sang Firestore, tối thiểu hai collections/subcollections.
- [ ] CRUD list/detail thật, ít nhất một filtered/sorted query, ít nhất một listener realtime cập nhật UI.
- [ ] Có seed hoặc quy trình tạo dữ liệu demo; restart app vẫn đọc được dữ liệu đã lưu.
- [ ] Mỗi bản ghi có định danh chủ sở hữu phù hợp; rules kiểm quyền ở máy chủ, không chỉ ẩn nút ở UI.
- [ ] Rules được lưu trong repo, có cách deploy và test allowed/denied cho chưa login, đúng owner, khác owner.
- [ ] Phạm vi đọc của Admin được thiết kế và kiểm riêng. Bất kỳ thay đổi nào so với owner-only của L/ADR-0019 phải được ghi nhận; không mở toàn bộ dữ liệu cho mọi user đăng nhập để web đọc được.

Nguồn: L tr.3–5,8,13–14; P tr.4; T về Admin.

## 3. Tích hợp dịch vụ và bằng chứng

| Hạng mục | Điều kiện hoàn thành | Bằng chứng cần lưu |
|---|---|---|
| Authentication | Google login, cancel/error, auth-state routing, profile ảnh/tên/email thật, logout thu hồi state user | Video trên điện thoại, ảnh Login/Profile, Firebase Users, kiểm protected route sau logout |
| Firestore | CRUD owner-scoped, query, realtime và rules đúng | UI đối chiếu Console, dữ liệu còn sau restart, log rules tests cho phép/từ chối |
| Cloudinary | App tạo PDF từ dữ liệu thật, upload có progress, lỗi/retry, nhận URL và lưu metadata Firestore | PDF mở được, progress/URL UI, asset Cloudinary và metadata Firestore |
| FCM | Quyền Android 13+, lấy/cập nhật token, foreground/background/terminated, inbox thật, tap đúng màn và entity | Token đăng ký thiết bị kiểm thử, ảnh/video ba trạng thái, gửi Console và đường gửi server nếu team triển khai, test từ chối quyền |
| Remote Config | Ít nhất hai defaults và hai giá trị từ xa thay đổi hành vi, Profile có giá trị hiện tại, fallback offline | Console trước/sau publish, app đổi hành vi không rebuild, kết quả offline |
| Crashlytics | Nonfatal được xử lý, nút gây crash native thật, UID/custom key, mở lại app và báo cáo xuất hiện Firebase | Video bấm nút/app đóng/mở lại, issue Console, UID/key, thời gian và phiên bản |
| Analytics | Plan thống nhất với code; login/logout/screen_view/detail/CRUD/export và ≥2 event riêng theo flow; UID, tham số đúng, không PII | DebugView từng loại event, liên kết thao tác với thời điểm phát và code caller |

Nguồn: L tr.5–7,14; P tr.5–22; T thay storage và bổ sung Crashlytics Admin.

Cloudinary cần có preset chỉ nhận định dạng/kích thước cho phép theo lựa chọn upload, không nhúng API secret trong mobile hoặc web. Với unsigned upload, preset không phải cơ chế phân quyền đọc file. Phải mô tả đúng khả năng truy cập URL của phương án đã chọn. Firestore metadata tối thiểu: ownerUid, tên file, thời điểm tạo/upload, URL, định danh asset; dung lượng và project/report ID nên được lưu để đối chiếu.

## 4. Web Admin và Crashlytics

- [ ] Web đăng nhập Admin thật và kiểm quyền bằng cơ chế đáng tin cậy; không dùng `isAdmin() => true` trong bản nộp.
- [ ] Admin xem kết quả crash qua web của team, không yêu cầu Admin thao tác Firebase Console.
- [ ] Web có list/detail lỗi, loại fatal/nonfatal, thời gian, app version, thiết bị và thông tin lỗi được phép hiển thị. Đây là đề xuất dữ liệu tối thiểu để kết quả có thể đối chiếu, không phải số màn do thầy quy định.
- [ ] Có loading/empty/error/refresh và chỉ rõ độ trễ nhận dữ liệu.
- [ ] Xác định nguồn báo cáo thật và đường đưa dữ liệu đến web, giữ credentials ở môi trường tin cậy.
- [ ] Phân biệt báo cáo Crashlytics đã nhận với bản ghi demo do app tự tạo. Ghi Firestore trước khi crash chỉ chứng minh đã yêu cầu crash.
- [ ] Dev đối chiếu issue trên Firebase, Admin mở kết quả tương ứng trên web; lưu bằng chứng cùng phiên bản, thiết bị và thời điểm.
- [ ] Các module khác như quản lý users, files, Remote Config chỉ triển khai khi cần cho flow/thiết kế; lời thầy chưa bắt buộc một dashboard Admin lớn.

Firebase có các đường export dữ liệu Crashlytics phục vụ báo cáo riêng. Cần chọn cách lấy dữ liệu phù hợp và chứng minh đường chạy thật; checklist không mặc định bắt buộc BigQuery.

Nguồn kỹ thuật: [Crashlytics export options](https://firebase.google.com/docs/crashlytics/export-data-to-cloud), [BigQuery export](https://firebase.google.com/docs/crashlytics/bigquery-export). Nguồn yêu cầu web: T.

## 5. Kiểm thử và review

- [ ] Mười kịch bản: login; F1; F2; F3; lỗi/phục hồi; CRUD entity; mọi top-level destination; Profile/Remote Config; PDF upload/open; logout.
- [ ] Mỗi test có account/seed/precondition rõ, bước chạy, expected/actual, assertion kết quả nhìn thấy, log và version app.
- [ ] MobAI: ≥10 `.mob`, review/edit script, full-run report, healing có diff và đánh giá assertion, cài bug thật để chứng minh fail rồi fix để pass. L tr.9–10.
- [ ] P dùng ARTEMIS thay MobAI, yêu cầu ≥3 lượt/case và exploratory 15–30 phút. T chưa giải quyết khác biệt này. Ghi riêng hai bộ; dùng công cụ thay thế chỉ khi có xác nhận của thầy, không mặc định Playwright hoặc Flutter tests thay thế được.
- [ ] Kiểm success/error của mỗi dịch vụ, bao gồm mất mạng, permission-denied/cancel và lỗi upload phù hợp.
- [ ] Có PR AI review cả code và Firestore Rules. Để đáp ứng cả L/P: ≥5 findings, ≥2 nhóm, ít nhất một security/robustness; quyết định accept/modify/reject có lý do; ≥3 accepted findings được sửa và có commit truy vết.
- [ ] Lưu prompt AI thật, không dựng lại prompt/results chưa từng chạy để điền hồ sơ.

## 6. Hồ sơ và báo cáo

| File/đầu ra | Nội dung phải hoàn thiện |
|---|---|
| README.md | Chủ đề/persona/flows, Figma + handoff Lab 2, cách chạy device thật/mobile/admin, Firebase/Cloudinary setup, tài khoản demo theo cách chia sẻ phù hợp, phiên bản |
| docs/architecture.md | Tầng MVVM, data flow, sequence diagrams, dependency injection, service/API ownership, Admin data path |
| docs/handoff-gaps.md | Điểm thiếu/mơ hồ/sai của handoff và cách giải quyết |
| docs/design-change-log.md | Thay đổi thiết kế, lý do và link Figma cập nhật/chú thích |
| docs/design-traceability.md | Requirement/flow → màn → ViewModel/service → test → ảnh/video/code |
| docs/fidelity-check.md | Mỗi màn Figma/app cùng 360×800dp, khác biệt/lý do, tokens/components/states; contrast, 48dp targets, 360/412dp |
| docs/analytics-plan.md | Event, trigger, typed params, câu hỏi sản phẩm, flow, caller và DebugView evidence |
| docs/implementation-ai-log.md | ≥6 entries khác phần app: prompt nguyên văn, output, verification, quyết định và lý do; khai báo mọi công cụ AI |
| docs/test-report.md | Case/starting state/results/logs, lỗi và rerun, healing/bug exercises; ghi đúng tool đã dùng |
| docs/code-review.md | PR/tool, file:dòng, finding/severity, quyết định/lý do và fix commit/before-after |
| Evidence | Ảnh/video device thật, Console, Admin web, Cloudinary, DebugView, test/review; có ID liên kết báo cáo |
| Source/repository | Rules và hướng dẫn deploy; không secrets; Git history qua các giai đoạn, ≥1 merged PR, repository truy cập được |

Dàn ý report: giới thiệu/persona/ba flows; yêu cầu và chỉ dẫn thầy; kiến trúc; Firestore/rules; từng dịch vụ và Cloudinary; Admin/Crashlytics; UI fidelity; testing/review/AI log; kết quả, giới hạn, bài học; liên kết evidence/source.

P yêu cầu report PDF 8–12 trang, slide PDF 12–15 trang, video 5–10 phút. L yêu cầu report khoảng 5–10 trang, video khoảng 3–5 phút. Mốc giao nhau để soạn bản nháp là report 8–10 trang và video khoảng 5 phút; đây là đề xuất, không thay xác nhận thời lượng cuối của giảng viên. T đã xác nhận cần slide giải thích nguyên lý. Không có nguồn nào chốt giá trị `[N]` commits/days, nên không tự đặt số.

## 7. Slide và giải thích công nghệ

Đề xuất 15 slide bám mức 12–15 của P:

1. Bài toán, persona, phạm vi Mobile và Admin.
2. Ba flows và tiêu chí thành công.
3. Kiến trúc tổng thể, ranh giới mobile/web/dịch vụ.
4. MVVM/Riverpod, một thao tác xuyên các tầng.
5. Google Sign-In, Firebase Auth UID, auth-state và logout.
6. Firestore model, CRUD/query/listener và offline/error.
7. Security Rules, owner/Admin, allowed/denied example.
8. PDF → Cloudinary → metadata Firestore → URL/open.
9. FCM token: nguồn cấp, app instance, token refresh, gắn user/device.
10. FCM send/receive: trusted sender, SDK/API, payload, lifecycle và deep link.
11. Remote Config: defaults/fetch/activate/cache, hai hành vi đổi thật.
12. Crashlytics: nonfatal/fatal, nút crash, mở lại và upload báo cáo.
13. Dữ liệu Crashlytics đến Admin web, quyền và độ trễ.
14. Analytics event plan và DebugView đối chiếu thao tác.
15. Test/review/fidelity, kết quả và bài học.

Mỗi công nghệ phải giải thích được: dùng làm gì; ai cấp/giữ dữ liệu; luồng request/response/event; quyền/credentials; file và hàm nào thực hiện; success/error demo; evidence ở đâu. Nếu có sender FCM riêng, ghi rõ server entrypoint và hàm gửi. Nếu chỉ gửi Console, nói đúng là chưa có sender nghiệp vụ riêng.

FCM token không phải Firebase Auth ID token hay mật khẩu. Flutter lấy registration token qua SDK, theo dõi thay đổi và đồng bộ nơi gửi khi cần. Gửi chương trình từ môi trường tin cậy; không nhúng server credentials trong mobile/web. Tham khảo: [Flutter FCM](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [FCM server environment](https://firebase.google.com/docs/cloud-messaging/server-environment).

## 8. Thứ tự hoàn thiện và kịch bản chấm

1. App compile/build/chạy device thật.
2. Auth và Firestore owner-scoped cho một flow hoàn chỉnh, rồi hai flow còn lại.
3. PDF/Cloudinary/metadata và quyền truy cập.
4. FCM, Remote Config, Analytics và Crashlytics thật.
5. Admin auth và đọc kết quả crash thật.
6. Test, review, sửa lỗi và thu evidence trên commit cuối.
7. Hoàn thiện report/slides/video và tập giải thích từ slide đến source.

Buổi demo: login device thật → CRUD và realtime → ba flows/nhánh lỗi → PDF upload/open → FCM và tap → Remote Config đổi hành vi → Analytics DebugView → nonfatal → crash thật → mở lại app → Dev đối chiếu Firebase → Admin xem kết quả web → chỉ file/hàm chính và giải thích nguyên lý.

Chuẩn bị dữ liệu crash đã xác minh làm dự phòng độ trễ, ghi rõ thời điểm và version. Không trình bày dữ liệu dự phòng như kết quả live vừa được nhận.
