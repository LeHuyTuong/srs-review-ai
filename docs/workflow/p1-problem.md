# P1 · PROBLEM — nội dung slide 01–06 (Guideline V11)

Nguồn: Gemini web soạn, Claude kiểm với code 2026-11-10 (3 vòng sửa). Chỗ `[CẦN SỐ]` / `[CHỜ DEMO]` phải điền trước khi chốt deck.

## Slide 01 · Overview (30 giây)

**Tiêu đề:** SRS Review AI giúp giảng viên quản lý dự án học vụ và phê duyệt tài liệu SRS của sinh viên trên thiết bị di động với trợ lý AI chấm theo rubric và kiểm chứng trích dẫn nguyên văn.

- **Định vị sản phẩm:** Hệ thống quản lý học vụ và rà soát tài liệu SRS (Report 3) cho môn đồ án SEP490 và các môn dự án phần mềm tại Đại học FPT.
- **Đối tượng sử dụng:** Giảng viên hướng dẫn và Sinh viên trên Flutter Mobile (Android); Quản trị viên trên Flutter Admin Web.
- **Giá trị cốt lõi:** Tập trung hoá luồng mở dự án theo lớp/nhóm (WF-01), tự động hoá bước chấm sơ bộ SRS theo tiêu chí ISO/IEC/IEEE 29148 có đối chiếu trích dẫn chống ảo giác (WF-02), đồng bộ dữ liệu qua Cloud Firestore kết hợp FastAPI.
- **Thông tin đồ án:** Môn học `<PRM392 hoặc PRM393>` · Nhóm thực hiện: Lê Huy Tường · GVHD: [CẦN SỐ / TÊN GVHD].

**Hình:** [ẢNH DEMO THẬT — chờ chạy lại] — Tổng quan Giảng viên + màn Đánh giá AI sau khi luồng `POST /review` chạy thật.

## Slide 02 · Context (30 giây)

**Tiêu đề:** Tài liệu SRS chiếm 16% điểm quá trình và 15% điểm bảo vệ cùng điều kiện ra hội đồng đợt 1, nhưng quy trình giao đề tài và duyệt bản nộp đang phân mảnh qua nhiều công cụ rời rạc.

- **Quy mô học vụ:** mỗi học kỳ một giảng viên phụ trách [CẦN SỐ] môn, [CẦN SỐ] lớp (mỗi lớp ~[CẦN SỐ] SV), [CẦN SỐ] dự án nhóm. *(Ghi chú nội bộ: app đang lệch giữa thẻ Tổng quan và màn danh sách — chốt trước khi điền.)*
- **Tầm quan trọng của SRS:** Đề cương SEP490 (ID 14065, QĐ 377/QĐ-ĐHFPT, 04/09/2026 — `README.md:12-21`): Report 3 chiếm 16% điểm quá trình và 15% điểm bảo vệ; phần báo cáo nào dưới 2/10 phải học lại; dưới 75% chức năng/màn hình hoặc dưới 20 use case (3–7 transactions) phải chờ bảo vệ đợt 2.
- **Công cụ hiện tại:** GV lập lớp, chia nhóm, gán đề tài, đặt hạn nộp bằng Excel/Google Sheets; SV gửi PDF/DOCX qua email, Zalo hoặc thư mục rời rạc.
- **Quy trình thủ công 4 bước:** (1) GV lập lớp, chia nhóm, gán đề tài → (2) SV gửi SRS qua kênh nhắn tin → (3) GV tải về đọc, tự đối chiếu rubric, ghi nhận xét → (4) GV cập nhật kết quả và theo dõi phản hồi trên bảng tính.

**Hình:** sơ đồ ngang 4 bước hiện trạng, phía trên thanh thông tin đề cương (16% quá trình · 15% bảo vệ · gate ≥ 20 UC & ≥ 75% màn hình · quy mô [CẦN SỐ]).

## Slide 03 · Problem (40 giây)

**Tiêu đề:** Ba điểm nghẽn trong khởi tạo dự án học vụ và kiểm duyệt SRS khiến giảng viên tốn thời gian rà soát thủ công, dễ lệch chuẩn rubric và thiếu cơ chế kiểm soát trạng thái tập trung.

- **Điểm nghẽn 1 — mở dự án rời rạc (WF-01):** kiểm điều kiện tiên quyết (nhóm thuộc lớp đang hoạt động, không vượt giới hạn thành viên, mỗi nhóm đúng 1 dự án, kế thừa RuleSet và cấu trúc Lab) dễ trùng lặp/sai khi làm tay trên nhiều danh sách.
- **Điểm nghẽn 2 — duyệt SRS thủ công và rủi ro "ảo giác" của AI thô (WF-02):** đọc hàng chục trang để tìm câu mơ hồ, thiếu điều kiện kiểm chứng, sai syllabus làm quá tải GV; chat AI thông thường dễ bịa trích dẫn và không bám rubric môn học.
- **Điểm nghẽn 3 — đứt gãy nộp bài, thông báo và kiểm soát quyết định (WF-02):** thiếu thông báo trực tiếp và thiếu ràng buộc ghi chú bắt buộc khi chuyển trạng thái (Chờ duyệt → Đang duyệt → Đã phê duyệt / Yêu cầu sửa / Không chấp nhận) khiến phản hồi thiếu nhất quán, dễ mất ngữ cảnh khi mất mạng.
- **Hạn chế / hướng phát triển:** chưa có luồng SV nộp lại bản sửa (v1 → v2); SV chưa có màn hình xem quyết định của GV — vai SV hiện chỉ có màn nộp bài.

| Pain point | Ai chịu | Số đo | Nguồn |
|---|---|---|---|
| **PP-01 (WF-01):** khởi tạo dự án thủ công dễ vi phạm ràng buộc học vụ (trùng dự án trên một nhóm, vượt sĩ số nhóm, lệch RuleSet giữa khoá – đợt – lớp) | GV, SV | Giới hạn mặc định 5 SV/nhóm (`academic_models.dart:83-86`). Số lớp/dự án mỗi GV, tỷ lệ sai sót, thời gian lập dự án thủ công: [CẦN SỐ] | `business-rules.md` (BR-01-01…05), `ui-flow-audit.md` |
| **PP-02 (WF-02):** rà soát SRS thủ công chậm; LLM thông thường bịa trích dẫn hoặc bỏ sót gate đề cương | GV, SV | 16% quá trình + 15% bảo vệ; < 2/10 học lại; gate ≥ 75% màn hình và ≥ 20 UC. Thời gian chấm thủ công 1 SRS: [CẦN SỐ] | `README.md:12-21`, `WORKFLOW_GUIDE.md` |
| **PP-03 (WF-02):** đứt gãy giữa khâu SV nộp tệp và hàng chờ của GV, tốn thao tác tìm kiếm, thiếu ràng buộc lý do khi Yêu cầu sửa / Không chấp nhận | GV, SV | Số yêu cầu chờ đồng thời & thời gian phản hồi trước khi có app: [CẦN SỐ]. Chỉ tiêu thiết kế Lab 2 (chưa đo thật): vào màn duyệt ≤ 3 thao tác, ≥ 90% duyệt không cần trợ giúp, 100% hiểu AI không tự duyệt | `test-cases-mobile.md` (TC-F2-02, TC-F2-17), `mobile-grading-compliance.md` §5 |

**Hình:** bảng 4 cột ở trung tâm, dưới là hộp trích nguyên văn gate SEP490 từ `README.md`.

## Slide 04 · Proposed Solution & Scope (40 giây)

**Tiêu đề:** Hệ thống kết hợp Flutter Mobile, Admin Web và FastAPI + Gemini để khép kín hai luồng mở dự án và duyệt SRS có kiểm chứng trích dẫn, tách phần Desktop sang phụ lục.

- **PP-01 → WF-01:** luồng Học kỳ → Môn học → Đợt học → Lớp → Nhóm → Dự án, kiểm ràng buộc tự động (chặn trùng dự án, chặn vượt sĩ số, kế thừa RuleSet và [CẦN SỐ] slot tài liệu chuẩn), đồng bộ qua Firestore và SQLite outbox `/sync/push`.
- **PP-02 & PP-03 → WF-02:** SV nộp SRS (PDF/DOCX/MD ≤ 30 MB, cấu hình qua Remote Config) lên Cloudinary và báo GV; GV chạy AI chấm theo rubric trên FastAPI (lỗi AI phải có trích dẫn khớp văn bản gốc ≥ 0.92, không khớp tự loại); GV ra quyết định cuối (Đã phê duyệt / Yêu cầu sửa / Không chấp nhận — hai loại sau bắt buộc lý do).
- **In-scope (MVP + demo):** Flutter Mobile (GV quản lý/duyệt, SV nộp SRS); Flutter Admin Web (crash_logs, analytics_events, Remote Config, gửi thông báo); FastAPI + Gemini (`/review`, `/sync`, `/notifications/submission`, xác thực Firebase token, kiểm chứng trích dẫn).
- **Out-of-scope & phụ lục:** Flutter Desktop (tách requirement F1–F9, Vision `/diagram`, `/ask`) ở phụ lục; màn SV xem quyết định của GV; luồng nộp lại v1 → v2; FCM qua service-account riêng; migration ownerId cho collection học vụ (CR-01).

| Pain point | Giải pháp | Workflow | Kết quả mục tiêu / kiểm chứng |
|---|---|---|---|
| PP-01 | Kiểm tự động 1 nhóm – 1 dự án, giới hạn thành viên, kế thừa RuleSet / [CẦN SỐ] slot tài liệu, offline-first qua SQLite outbox | WF-01 | Tạo dự án +1 bản ghi, chặn lưu khi trống tên hoặc sai hạn nộp (FL01–FL03); đồng bộ `/sync` của dự án ở FL01 [CHỜ DEMO]; FL09 chỉ kiểm cơ chế outbox bằng việc tạo **học kỳ**, không phải dự án |
| PP-02 | FastAPI chấm theo `rubric.json` qua Gemini + lọc trích dẫn (exact hoặc fuzzy ≥ 0.92, sai bị đếm vào `dropped_issue_count`) | WF-02 | Điểm theo rubric kèm nhận xét có trích dẫn nguyên văn, GV giữ quyền quyết định cuối ([CHỜ DEMO] lượt `POST /review` từ Mobile) |
| PP-03 | Nộp Cloudinary theo Remote Config (30 MB), đẩy thông báo, kiểm soát trạng thái Chờ duyệt → Đang duyệt → 3 trạng thái cuối | WF-02 | Chặn Yêu cầu sửa khi trống ghi chú, giữ Đang duyệt (FL05); nộp Cloudinary (FL11) và duyệt giảm số chờ (FL04): [CHỜ DEMO] |

**Hình:** nửa trên bảng ánh xạ; nửa dưới hai hộp — xanh IN-SCOPE (Mobile GV + SV nộp bài · Admin Web · FastAPI + Gemini + Firebase/Cloudinary), xám OUT-OF-SCOPE (Desktop · màn SV xem quyết định · nộp lại v1 → v2 · FCM service-account & migration CR-01).

## Slide 05 · Main Actors (30 giây)

**Tiêu đề:** Bốn nhóm tác nhân (ba vai người dùng và các dịch vụ đám mây) tương tác theo phân quyền dựa trên Firebase UID, không nhúng khoá bí mật phía client.

- **Giảng viên (Mobile):** quản lý học kỳ, môn, đợt, lớp, sinh viên, nhóm; mở dự án SRS (WF-01); chuyển yêu cầu Chờ duyệt → Đang duyệt, chạy AI, xem điểm theo rubric, ra quyết định, xuất báo cáo `.md` (WF-02).
- **Sinh viên (Mobile):** đăng nhập Google với `role = "student"` trên Firestore, dùng màn nộp bài chọn lớp và dự án, kiểm tệp theo Remote Config (pdf, docx, md ≤ 30 MB), tải lên Cloudinary và báo server (WF-02).
- **Quản trị viên (Admin Web):** đăng nhập Firebase Auth (quyền ở `admins/{uid}`), giám sát `crash_logs`, thống kê `analytics_events`, chỉnh Remote Config, phát thông báo.
- **Hệ thống ngoài:** Firebase (Auth Google Sign-In, Firestore, FCM, Remote Config, Analytics, Crashlytics), Cloudinary (lưu tệp SRS), Gemini API (`gemini-3.5-flash-lite`, dự phòng `gemini-3.1-flash-lite`, chỉ gọi qua FastAPI).

**Hình:** bảng 4 hàng (Actor | Vai trò & nền tảng | Quyền chính | Cơ chế phân quyền: `users/{uid}.role`, `admins/{uid}`, `require_app_token` ở `server/app/api/deps.py:115`).

## Slide 06 · Main Features (45 giây)

**Tiêu đề:** Hệ thống tổ chức thành bốn nhóm tính năng, lấy hai workflow lõi từ mở dự án đến nộp và phê duyệt SRS có AI hỗ trợ làm trục cho phần Thiết kế, Demo và Kiểm thử.

- **WF-01 · Mở dự án SRS cho nhóm sinh viên:** Trigger — GV cần giao đề tài cho nhóm trong lớp đang dạy; Bước — tra lớp, kiểm nhóm hợp lệ, tạo dự án kèm hạn nộp, đồng bộ nền về FastAPI; Kết quả — dự án ở trạng thái Đang thực hiện (`active`), tổng dự án +1, server nhận bản ghi đồng bộ [CHỜ DEMO].
- **WF-02 · Nộp SRS và duyệt có AI hỗ trợ:** Trigger — SV chọn tệp SRS hợp lệ, nộp lên Cloudinary và báo GV; Bước — GV chuyển Chờ duyệt → Đang duyệt, chạy AI qua FastAPI + Gemini lấy điểm theo rubric, xác nhận quyết định; Kết quả — Đã phê duyệt (hoặc Yêu cầu sửa / Không chấp nhận kèm lý do), bộ đếm chờ trên Tổng quan −1.
- **Tính năng hỗ trợ trên Mobile:** tìm kiếm, lọc, Saved Views; quản lý học kỳ, môn, RuleSet, danh bạ SV (nhập CSV/QR); trung tâm thông báo lọc theo Hạn nộp; đồng bộ ngoại tuyến qua SQLite outbox (FL08, FL09).
- **Admin Web & phụ lục Desktop:** theo dõi `crash_logs`, [CẦN SỐ] sự kiện `analytics_events`, Remote Config (`max_upload_file_size_mb`, `allowed_srs_file_types`, `ai_review_enabled`) không cần build lại; Desktop ở phụ lục.

**Hình:** hai thẻ ngang WF-01 (PP-01) và WF-02 (PP-02, PP-03), mỗi thẻ có Actor · Trigger · Bước & BR · Chuyển trạng thái; dưới là thanh tính năng hỗ trợ + phụ lục Desktop.

## Phụ: Lab 2 so với V11

**Lab 2 có nhưng V11 không cần trên slide chính:**

| Nội dung Lab 2 / Lab 3 cũ | Vì sao | Xử lý |
|---|---|---|
| 25 route màn hình rời rạc, menu chức năng (`design-traceability.md`) | W06/W09: màn hình và CRUD không phải workflow | CRUD vào thanh tính năng phụ slide 06; sitemap chỉ ở slide 11 |
| Bảng design token từng pixel, 42 cặp ảnh React vs Flutter | Slide là tổng quan, không phải tài liệu handoff | 1 dòng ngôn ngữ thiết kế + 4 trạng thái ở slide 11; bảng đo vào phụ lục A1 |
| Mỗi dịch vụ Firebase một slide (`lab3-slides.html` slide 3–12) | V11 tổ chức Design theo kiến trúc, không theo SDK | Gom vào slide 09–10; thể hiện hành vi thật trong bước WF-01/WF-02 lúc demo |
| Lịch sử port từ React cũ (`react-flutter-mapping.md`) | Hội đồng chấm sản phẩm hiện hành | Bỏ; chỉ giữ một mục "Sau góp ý → đã sửa gì" ở slide 11 |

**V11 cần nhưng Lab 2 thiếu:**

| Yêu cầu V11 / Workflow | Lab 2 thiếu | Bù bằng |
|---|---|---|
| Số liệu hiện trạng/khảo sát (slide 02–03) | Không có số đo thời gian chấm, tỷ lệ sai sót, cỡ mẫu | Giữ số đề cương SEP490; còn lại [CẦN SỐ] |
| Workflow xuyên actor qua backend thật (W03, slide 06, 18–19) | Chỉ phía GV trên dữ liệu giả lập, chưa gọi `/review` thật | Màn SV nộp SRS (`student_upload_screen.dart`, FL11) + GV duyệt (FL04) — nhưng FL11 chưa chạy, FL04 chưa gọi `POST /review` (`artemis-run-log.md:126`); cần nối dây và chạy lại |
| Sơ đồ cấp hệ thống (slide 07–16) | Chỉ có user flow cấp màn hình | `docs/uml/` + `docs/workflow/*.md`; nhãn trạng thái tiếng Việt |
| Test nhiều tầng + hạn chế trung thực (slide 21–23) | Không có E2E trên thiết bị thật | `artemis-run-log.md`, `test-cases-mobile.md`, `code-review.md`; ghi rõ các hạn chế ở slide 23 |
