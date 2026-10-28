# Final audit — Supervisor Flutter Mobile

> **Phase 4.5:** [Pre-Firebase fixes](../pre-firebase-fixes/README.md) là báo cáo mới nhất về sửa AUD-U01/A02/B03/B02/B01, scoped MVVM cleanup và migration boundary còn lại. Các finding/hash/test counts của Final Audit bên dưới là lịch sử trước sửa; xem báo cáo Phase4.5 để biết trạng thái hiện tại.

> **Bản sửa tiếp theo:** [Supervisor-only Login](../supervisor-only-login/README.md) ghi nhận thay đổi Login/session/route guard và kết quả kiểm chứng mới. Các kết quả audit và hash bên dưới là baseline trước bản sửa; không còn đại diện cho hash source sau bản sửa. Những issue khác của Final Audit vẫn giữ nguyên trạng thái.

Ngày audit: 25/10/2026. Flutter: `D:/SRS-Review-AI-Mobile`; React đối chiếu, chỉ đọc: `D:/UI AI Review`.

**Kết luận:** nền tảng Riverpod/DI và nhiều luồng Supervisor hoạt động, nhưng chưa đáp ứng đầy đủ Lab 3 và cần refactor có mục tiêu trước Firebase. Không cần viết lại ứng dụng. Chưa xác nhận P0; đã tái hiện năm lỗi quan trọng về tìm kiếm, phiên đăng nhập và tính nhất quán dữ liệu/trạng thái. Không suy ra chất lượng toàn bộ sản phẩm chỉ từ 185 test PASS.

Phạm vi do người dùng xác nhận: **Supervisor dùng Flutter Mobile; Student dùng React Web**. Thiếu Student Mobile là N/A. Nhận định ngược lại trong báo cáo Phase 4 cũ không còn áp dụng. Luồng Student Web→backend→Supervisor Mobile vẫn cần kiểm chứng khi có backend; audit này không triển khai luồng đó.

## Tài liệu audit

| Báo cáo | Nội dung |
|---|---|
| [Lab 3 compliance](lab3-compliance.md) | Ma trận 40 yêu cầu, nguồn/trang, trạng thái, gap và mức độ |
| [Architecture](architecture-audit.md) | Toàn bộ 96 file Dart trong lib, dependency, MVVM, state, model và design system |
| [Business rules](business-rules-audit.md) | Đối chiếu React, bất biến dữ liệu, các lỗi và cách tái hiện |
| [Native UI flows](ui-flow-audit.md) | Tám flow Supervisor, đối chiếu ba flow Lab 2, phạm vi thực sự đã thao tác |
| [Firebase readiness](firebase-readiness.md) | READY / NEEDS REFACTOR / BLOCKED theo từng ranh giới tích hợp |
| [Issues](issues.md) | 12 finding có severity, expected/actual, evidence, gợi ý sửa và ảnh hưởng rubric |

## 1. Lab 3 compliance

Đã đọc toàn bộ 18 trang [đề Lab 3 gốc](<D:/PRM393 - Lab 3 Cloud-Enabled Mobile App (Firebase, Patrol, AI Code Review).pdf>). Nội dung yêu cầu **Google ARTEMIS**, dù tên file/footer còn ghi Patrol. Lưu bản trích xuất tại [lab3-original-text.txt](lab3-original-text.txt); trang kiến trúc/Firebase đã được render và kiểm tra hình ảnh.

Đạt các nền tảng: Riverpod, DI ở các ranh giới academic/device hiện tại, ViewModel có thể unit test, không phát hiện View gọi HTTP/Firebase SDK trực tiếp. Theme và shared components đã có. Đáp ứng một phần: MVVM nghiêm ngặt, state lifecycle, design-system consistency, full-flow/alternate/error coverage và tài liệu kiến trúc.

**NOT IMPLEMENTED:** real data, cả sáu Firebase service bắt buộc, Supervisor tạo file/report rồi upload, ARTEMIS suite và evidence theo đề. Đây là gap bắt buộc của bài cuối, không phải lý do kết luận fake repository hiện tại bị lỗi. Các lỗi fake-state đã tái hiện được ghi riêng.

**NOT VERIFIED:** Figma Final UI/prototype/approval, round trip Web↔Mobile qua backend, các bằng chứng console và submission chưa cung cấp. Đã đọc các tài liệu Lab 2 hiện có; không tìm thấy đúng đường dẫn `design/DESIGN.md` và `handoff/flutter-handoff.md`. Figma bridge không kết nối. Không tính phần trăm hoàn thành hoặc điểm rubric tùy ý.

## 2. MVVM architecture

Đã rà 96 file Dart / 15.521 dòng trong `lib/`. Không phát hiện ViewModel phụ thuộc screen/widget cụ thể; repository/service có khả năng inject. Ba vòng import cùng layer là coupling cần cân nhắc, không tự động là lỗi runtime hoặc dependency đi ngược tầng.

Chưa đạt strict MVVM vì View còn lọc, xếp hạng, sắp xếp và tổng hợp dữ liệu nghiệp vụ. Session chưa có identity/UID thực; logout chỉ xóa session, không xóa cache. Contract load/commit toàn snapshot và raw-map DTO/domain chưa phù hợp để thay trực tiếp bằng Firestore. Xem AUD-A01/A02/A03.

## 3. Business-rule consistency

Source và test hiện có hỗ trợ nhiều quy tắc đúng: bảo vệ tham chiếu/archive, giới hạn thành viên/sĩ số, phân biệt override null và empty, clone/remap, rule version/snapshot, tách ghi chú Student với phản hồi Supervisor, AI không tự phê duyệt. Không xác nhận lỗi sửa ngược lịch sử hoặc rò ghi chú Student vào phản hồi chính thức.

Bốn probe độc lập tái hiện: mã Course chuẩn hóa trùng ID làm ghi đè; project giữ class link sau xóa nhóm bị thiếu trong Dashboard; mutation làm reset bộ lọc học kỳ; cache còn sau đổi phiên. Các điểm yếu tương tự trong React được ghi rõ, không lấy React làm lý do chấp nhận mất dữ liệu ở Flutter.

## 4. UI flow results

Đã chạy app Android thật từ `lib/main.dart`, thao tác tám nhóm flow ở 390dp: Authentication; Academic; Class/Group; Project; Review; Rule Set; Management; Notifications. Đã quan sát tạo Course/Project, sửa Offering, enrollment, giới hạn nhóm, liên kết Project, review/AI mẫu/approve/history, rule save/cancel/version/assignment, date picker, directory empty/recovery và notification→đúng detail→Back.

Các đường đã thao tác phần lớn hoạt động; **không kết luận toàn bộ E2E PASS**. Search mất focus sau ký tự đầu đã tái hiện native (AUD-U01). Logout chặn quay lại màn được bảo vệ nhưng cache vẫn còn (AUD-A02). File/AI/notification hiện là mẫu; lỗi mạng, Google cancellation và liên thông backend chưa được kiểm chứng. Tám checklist này không thay thế ba flow Lab 2: phần Supervisor đã được map riêng; phần Student Web/backend còn NOT VERIFIED.

## 5. Responsive / accessibility

Đã kiểm tra form có rủi ro ở **360dp và 412dp**, cùng các flow chính ở **390dp**. Bàn phím Android/Gboard thực sự hiển thị, có log IME; các nút form được chọn vẫn truy cập được. Không quan sát overflow/crash/modal kẹt tại checkpoint đã kiểm tra. Có 26 ảnh JPEG chọn lọc, không chạy lại screenshot sweep.

12 cặp màu token opaque được tính đạt AA, tỷ lệ thấp nhất 4,637:1; body text mặc định 14sp. Chưa đo mọi semantic touch target ≥48dp, TalkBack, large text hay mọi trạng thái overlay/disabled. Figma fidelity vẫn NOT VERIFIED. Không đánh đồng icon 24px với vùng bấm 24dp nếu có cả row tương tác.

## 6. Automated tests và evidence

| Kiểm tra mới trong audit | Kết quả | Evidence |
|---|---|---|
| Flutter analyze, một lần | No issues found | [analyze.log](analyze.log) |
| Bộ unit/widget hiện có, một lần | **185/185 PASS** | [flutter-test.log](flutter-test.log) |
| Targeted audit probes, một lần | **4/4 FAIL**, tái hiện bốn defect; không phải kết quả PASS | [audit-probes.log](audit-probes.log), [probe source](audit_probes_test.dart.txt) |
| Native Android manual | Các đường/giới hạn nêu trong UI report | [ui-actions.json](ui-actions.json), ảnh và log IME/runtime |
| Flutter integration_test | Đã đọc source/evidence hiện có; không chạy lại trong audit này | Phân loại trong UI report |
| Google ARTEMIS | Chưa có SDK/suite/run evidence | Compliance matrix |

Probe được tạo riêng trong thư mục audit, chạy dưới đuôi `.dart`, sau đó lưu `.dart.txt` làm evidence, không đưa vào test discovery bình thường. Không sửa test cũ để làm PASS. Thao tác native thủ công và Flutter integration_test **không được gọi là ARTEMIS**.

## 7. Firebase readiness

**READY để tái sử dụng:** Riverpod DI, các lớp VM/repository hiện có làm nền, phần state/route/detail và gateway thiết bị. **NEEDS REFACTOR:** identity-scoped lifecycle, contract/query/command/DTO/error, projection chung, auth/telemetry/config/export adapters. **BLOCKED:** security/ownership policy và cấu hình backend chưa xác minh; Storage phụ thuộc identity cùng workflow tạo file.

Fake snapshot/revision guard chỉ chứng minh nhất quán trong mô hình hiện tại; không chứng minh multi-user transaction/offline/security. Không thể coi tích hợp Firebase là chỉ thay một implementation.

## 8. Top 10 ưu tiên

P1 bao gồm defect đã tái hiện, yêu cầu kiến trúc nghiêm ngặt và final-submission gate; xem loại từng hàng để tránh đánh đồng.

| Ưu tiên | Issue | Loại và tác động |
|---|---|---|
| 1 | AUD-U01 | Native defect: search mất focus sau ký tự đầu |
| 2 | AUD-A02 | Probe defect: logout giữ dữ liệu phiên trước |
| 3 | AUD-B03 | Probe defect: Course slug collision ghi đè dữ liệu |
| 4 | AUD-B02 | Probe defect: Dashboard bỏ project còn hợp lệ sau detach nhóm |
| 5 | AUD-B01 | Probe defect: mutation reset học kỳ Dashboard |
| 6 | AUD-A01 | Source violation: business projection còn trong View builders |
| 7 | AUD-A03 | Readiness gap: raw-map / toàn snapshot / ownership contracts |
| 8 | AUD-F02 | Final gate: thiếu Supervisor report/export→upload |
| 9 | AUD-F01 | Final gate: real data và sáu Firebase service chưa triển khai |
| 10 | AUD-T01 | Final gate: thiếu ARTEMIS plan, suite và run evidence |

Ngoài top 10: AUD-D01 — formal review/submission/Figma evidence và tài liệu cũ; AUD-U02 — design-system/accessibility exceptions. Không có P0 được xác nhận.

## 9. Cần hoàn thiện trước Firebase

1. Sửa năm defect đã tái hiện; bảo vệ stable identity/ID, dữ liệu và bộ lọc qua mutation/đổi phiên.
2. Chuyển business projection khỏi build sang VM/domain, dùng chung cách suy ra academic context giữa Dashboard và quản lý.
3. Chốt identity/ownership, typed DTO/command/query/error contracts và lifecycle theo user; xác định transaction/version invariants trước Firestore.
4. Chốt nội dung report Supervisor và ranh giới tạo file/upload; không thêm Student Mobile.

Sau đó mới tích hợp một lát cắt hẹp: Google Sign-In→user scope→real-data query với access rules và failure states, rồi mở rộng sáu service. Đây là đề xuất, chưa thực hiện.

## 10. Cần hoàn thiện trước nộp Lab 3

Sau bước nền tảng, hoàn thành real-data flows và sáu Firebase service cùng failure cases/console evidence; report→Storage; ≥7 analytics events; hai Remote Config values có hành vi; FCM đủ app states và received feed; Crashlytics handled/fatal proof theo đề.

Hoàn thiện ARTEMIS ≥10 case, structured assertions, native interactions, analytics assertion, ≥3 runs/case với timing/pass/flaky evidence và Pro exploration 15–30 phút. Khép ba flow Lab 2 đúng phạm vi Web/Mobile; xác minh Figma; cập nhật sequence diagram/traceability, review quyết định accept/modify/reject và ≥3 linked fix commits, AI disclosure, report PDF 8–12 trang, slides PDF 12–15 trang, video demo 5–10 phút cùng các link được kiểm chứng. Danh sách này là nghĩa vụ trước nộp, không yêu cầu làm hết tài liệu/video trước bắt đầu tích hợp.

## Trả lời Q1–Q5

**Q1.** Đáp ứng một phần MVVM + Riverpod: Riverpod/DI đạt; business trong View và lifecycle/cache khiến chưa đạt đầy đủ yêu cầu kiến trúc.

**Q2.** Đạt các nền tảng DI/state framework/test/theme; còn thiếu real data, sáu Firebase, report/upload, ARTEMIS và formal submission evidence. Figma và Web/backend/Mobile round trip chưa kiểm chứng. Chi tiết từng yêu cầu trong matrix.

**Q3.** Nhiều đường Supervisor đã hoạt động thật trên Android, nhưng không thể tuyên bố mọi flow đúng E2E; có search defect và lỗi cross-module/session, còn real-service/error paths chưa triển khai hoặc chưa kiểm chứng.

**Q4.** Ưu tiên search focus, cache logout, Course ID overwrite, Dashboard thiếu detached project và reset filter; tiếp theo MVVM projection và backend contracts.

**Q5.** Nên refactor có mục tiêu trước, rồi tích hợp Firebase từng lát cắt. Không cần viết lại app hoặc mở rộng Student Mobile.

## Integrity và điểm dừng

[source-integrity.json](source-integrity.json) đối chiếu hash **189 file gốc** với baseline: không file nào thay đổi. Phạm vi manifest gồm lib/test/integration_test/assets/tools/test_driver và pubspec.yaml/lock; không khẳng định mọi file generated/build cache đều bất biến. React git status sạch khi kiểm tra cuối. Chỉ tác giả hóa tài liệu/evidence trong thư mục này; không sửa Flutter source/fixture/test cũ, không Firebase integration, không commit/push. Công cụ Flutter có tạo/làm mới build cache để kiểm thử như bình thường.

Audit-only data nằm trong fake repository của phiên chạy; app được khởi động lại và để signed out, cấu hình emulator size/density/IME được trả về giá trị ban đầu. Các gợi ý sửa chưa được thực thi. Audit kết thúc tại báo cáo này.
