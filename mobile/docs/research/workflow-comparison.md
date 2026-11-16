# So sánh workflow cho SRS Review AI và PRM393

Ngày xác minh: **26/10/2026 (Asia/Saigon)**. Nghiên cứu/lập kế hoạch; chưa triển khai A hoặc B. Tính năng vendor được chứng minh bằng nguồn chính thức trong [nghiên cứu nền](google-ai-studio-firebase.md).

## 1. Quyết định đề xuất

**B là phương án chính phù hợp nhất:** tiếp tục Flutter Android Supervisor và Flutter Web của nhóm, cùng Firebase project, SDK trực tiếp qua services, Gemini Developer API qua Firebase AI Logic, Web static trên Firebase Hosting. Giữ MVVM/Riverpod và giá trị 213 regression tests; tích hợp từng adapter thay fake sau khi Backend chốt contracts.

**A phù hợp prototype công cụ ở sandbox, chưa phù hợp làm đường nộp Final mặc định.** AI Studio Web tạo React + Node và publish Cloud Run; Android native tạo Kotlin/Compose. Final yêu cầu Mobile Flutter, no custom server, AI Logic và shared Dart package; hình kiến trúc Final p.3 ghi Cloud Run ngoài phạm vi. Đây là khác biệt kiến trúc và tiêu chí, không phải đánh giá chất lượng của AI Studio nói chung. [Build Mode](https://ai.google.dev/gemini-api/docs/aistudio-build-mode), [Android](https://ai.google.dev/gemini-api/docs/aistudio-android), [Firebase integration](https://firebase.google.com/docs/ai-assistance/ai-studio-integration).

## 2. Nguồn đặc tả và cách đọc ma trận

Đã đọc trực tiếp hai PDF, xác minh 26/10/2026:

- [PRM393 Lab 3 — 18 trang](<D:/PRM393 - Lab 3 Cloud-Enabled Mobile App (Firebase, Patrol, AI Code Review).pdf>): task pp.2–3; MVVM pp.4–6; Firebase pp.6–8; ARTEMIS pp.8–9; review p.10; rubric pp.12–15. Tên file/footer có Patrol nhưng nội dung yêu cầu **Google ARTEMIS**.
- [PRM393 Final — 9 trang](<D:/PRM393 - Final Assignment One Complete System on Firebase.pdf>): task p.2; kiến trúc và hình p.3; backend/Web p.4; Web/AI/testing p.5; testing/deliverables p.6; rubric pp.7–8; rules/cross-role templates p.9.
- Baseline local: [grading compliance](../mobile-grading-compliance.md), [test coverage](../mobile-test-coverage.md), [Firebase contracts](../mobile-firebase-contracts.md), [roadmap](../mobile-phase5-roadmap.md). Các file này có giá trị inventory; **PDF và hình gốc là nguồn ưu tiên** khi diễn giải chưa đủ.

“Phù hợp” trong bảng là khả năng của phương án sau khi triển khai và có evidence; không có dòng nào tự chứng nhận project hiện tại đã đạt Final. 213 tests là unit/widget baseline theo báo cáo Phase 5.0; chưa chứng minh Auth, Firestore, AI, Rules, ARTEMIS hoặc Web↔Mobile.

## 3. Hai phương án cụ thể

### A. Workflow Build Mode lead đề xuất

Figma final/tokens → Stitch exploration/export → source mẫu được lưu/review qua GitHub → AI Studio import → agent thêm Firebase → demo Web/Android native.

- Chặng import/sync GitHub được mô tả trong tài liệu Build tổng quan. Trang Android chuyên biệt vẫn ghi ZIP only, chưa có GitHub export; không cam kết toàn chuỗi cho Android. [Build](https://ai.google.dev/gemini-api/docs/aistudio-build-mode), [Android](https://ai.google.dev/gemini-api/docs/aistudio-android).
- Web mặc định React + Node server; Gemini chạy server-side với secret, Publish lên Cloud Run. Dù hạ tầng được quản lý/serverless, Node do app quản lý vẫn là server logic, khác kiến trúc client SDK + rules của Final.
- Android native có thể dùng Firestore/Auth/AI Logic/App Check tự cấu hình nhưng dùng Kotlin/Compose, không giữ code Dart hiện tại.
- Stitch có image/design/code context, DESIGN.md và export sang AI Studio. Chưa xác minh import nguyên Figma file hay GitHub round-trip Stitch; không coi chuỗi là chuyển đổi lossless. [Stitch](https://blog.google/innovation-and-ai/models-and-research/google-labs/stitch-ai-ui-design/).
- Agent-generated security rules và IAM cần kiểm soát; existing Firebase project đã có Firestore là một hạn chế integration hiện hành. [Firebase integration](https://firebase.google.com/docs/ai-assistance/ai-studio-integration).

Nếu chỉ lấy React UI output rồi bỏ Node, thay runtime AI bằng Firebase AI Logic JS, deploy static Hosting và giữ Flutter Mobile, có thể tiến gần Final hơn. Nhưng đó là **phương án A đã điều chỉnh đáng kể**, không chứng minh Build Mode default đáp ứng. React không dùng trực tiếp package Dart; phải xin cách nghiệm thu shared package/architecture rõ ràng trước khi chọn.

### B. Flutter hiện tại + Firebase SDK + Firebase AI Logic

Figma final/approved handoff + DESIGN.md → hai client Flutter tiếp tục phát triển trong IDE → Backend chốt schema/rules/index/roles → Firebase SDK adapters qua services → một Firestore database → Firebase Hosting + APK → regression, rules tests, ARTEMIS và live cross-role demo.

- Shared `packages/core/` sau khi nhóm thống nhất: models, codecs/contracts, Firestore services; chia sẻ theme/widgets phù hợp. Không ép chia sẻ VM của các vai trò khác nhau. Hiện chưa tổ chức lại workspace; đây là kế hoạch Final.
- Giữ `View → ViewModel → Repository → Service → SDK`; Provider/Riverpod inject dependencies. Không serialize toàn `AcademicSnapshot` thành một document để thay backend nghiệp vụ. [Flutter guide](https://docs.flutter.dev/app-architecture/guide), [Firebase Flutter](https://firebase.google.com/docs/flutter/setup).
- AI service dùng `firebase_ai`, App Check, RC model/prompt/flag, typed JSON và người dùng xác nhận. [AI Logic](https://firebase.google.com/docs/ai-logic/get-started), [Structured output](https://firebase.google.com/docs/ai-logic/generate-structured-output).
- Web release static trên Hosting, không rewrite sang Functions/Run/App Hosting. [Hosting](https://firebase.google.com/docs/hosting).
- AI Studio có thể dùng thử prompt/JSON với dữ liệu tổng hợp; Stitch dùng khám phá UI khi có nhu cầu. Hai công cụ không cần nằm giữa Web/Mobile và Firestore lúc runtime.

## 4. So sánh triển khai

| Tiêu chí | A: Build Mode mặc định | B: Flutter + Firebase |
|---|---|---|
| Tốc độ dựng demo mới | Có lợi cho app mẫu prompt-to-preview | Cần tự tích hợp SDK nhưng đã có UI/logic/tests |
| Bảo toàn Phase 5.0 | Kotlin/React không tái sử dụng trực tiếp Dart source/tests | Giữ invariants, bổ sung adapter/realtime/security tests |
| Flutter Android | Chưa có workflow build Flutter được bảo đảm | Đúng nền tảng hiện tại |
| Flutter Web | React mặc định, không có bằng chứng chuyển Flutter tự động | Đúng phân công Web của team |
| MVVM/Riverpod | Cần review/restructure; native ViewModel không thay Flutter MVVM | Tiếp tục pattern đã có, còn các gap phải đóng |
| Shared Dart package | React/Kotlin không dùng trực tiếp | Hai client Flutter dùng chung được |
| Firebase hiện hữu | Integration có limitation project đã có Firestore | SDK đăng ký Android/Web vào project chuẩn của Backend |
| AI runtime | Web default Gen AI SDK server; Android AI Logic | AI Logic Flutter theo yêu cầu Final |
| Host và custom server | Cloud Run + Node Web default | Hosting static, SDK/rules, không custom server |
| Quyền/rules | Agent có thể sinh/deploy/ghi đè rules | Backend sở hữu rules, test/deploy có review |
| Realtime Web/Mobile | Có thể nếu hai app cùng backend/path/permissions, cần cấu hình | Hỗ trợ trực tiếp qua FlutterFire streams |
| Chi phí | Starter eligibility hoặc billing; AI quota và shared Firestore quota riêng | Emulator trước; Spark/AI free tier nếu đủ điều kiện và quota |
| Evidence môn học | Phải làm riêng; preview thành công không đủ | Phải làm riêng; 213 tests chưa đủ |

Đánh giá công sức định tính, không báo thời gian chắc chắn khi chưa có schema/SDK/credentials. B giảm rủi ro viết lại kiến trúc và bỏ coverage; không loại bỏ công việc Backend, security, AI và E2E.

## 5. Đối chiếu Lab 3

| Yêu cầu / trang | A mặc định | B / việc phải làm và evidence |
|---|---|---|
| Mobile Flutter Android; toàn UI Lab 2 ≥8 screens, đủ 3 flows/error/recovery (pp.1–3) | Native Kotlin hoặc mobile Web không đáp ứng Flutter | Giữ Supervisor scope; mapping Figma final được duyệt, chạy đủ routes/flows; confirm phần Student ở Web |
| MVVM Provider/Riverpod, dependency hướng xuống, SDK qua service, state do VM quản (pp.4–5) | Sinh app không tự chứng minh tuân thủ | Giữ MVVM/DI; audit notifications/business projections, architecture folder/layer/sequence/VM-service table |
| Tokens/components/states, 48dp/14sp, 360/412dp (p.6) | Stitch/Compose/React không tự giữ handoff | Đối chiếu tokens/widgets; screenshots, semantics, accessibility và recovery states |
| Dữ liệu thật, generate file + cloud upload (p.3, p.6) | Agent Firebase không tự thực hiện đúng report nghiệp vụ | Auth/Firestore thật; export theo dữ liệu Supervisor, per-UID Storage rules/progress/URL nếu nghiệm thu Lab 3 riêng được chốt |
| Google Sign-In, cancel/auth routing/logout clear (p.6) | Auth generated cần test máy thật, role rules vẫn riêng | Firebase Auth adapter, Google cancel/error, wrong role, cleanup/cache/pending write policy |
| FCM foreground/background/terminated, Android 13 permission, tap route (p.7) | Không mặc định app generated đã có | Tích hợp/test notification lifecycle; Firestore inbox không thay bằng chứng FCM |
| Analytics ≥7 events typed/no PII/UID + DebugView (pp.7–8) | Không tự đạt vì có Gemini | Event plan trước code; screenshots từng event, kiểm tra một event trong E2E |
| Crashlytics real nonfatal + test crash, UID/key (p.7) | Phải làm riêng | Adapter reporter và console evidence trên Mobile |
| Remote Config ≥2 params có tác động, defaults, no rebuild (p.7) | Phải làm riêng | AI flag và page-size/config phù hợp; before/after trên thiết bị |
| ARTEMIS ≥10 cases, 3 runs/case, structured assertions, native interaction, Pro exploratory 15–30 phút (pp.8–9) | Browser emulator preview không thay ARTEMIS | Giữ unit/widget tests và bổ sung ARTEMIS độc lập, pin commit, traces/replays, pass rate, flaky explanations |
| AI review ≥5 line findings, ≥2 kinds, ≥3 fix commits (p.10) | Code generation không thay review decision record | Review diff khi triển khai; finding/decision/fix evidence. Nghiên cứu này không tạo commit |

**Chi phí Lab 3 cần xử lý trước:** đề p.1 ghi Spark đủ nhưng [Storage FAQ hiện hành](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024) yêu cầu Blaze. Không hứa hoàn thành cloud upload trên Spark. Cần giảng viên xác nhận cách nghiệm thu hoặc cấp phép billing riêng; không tự thay dịch vụ hoặc làm giả console evidence.

## 6. Đối chiếu Final và rubric

| Yêu cầu / trang, nhóm điểm | A mặc định | B / điều kiện để có bằng chứng |
|---|---|---|
| Hoàn tất Lab 2/Lab 3; Firestore + realtime inbox (p.2; Mobile 2.0 điểm p.7) | Viết lại native không đạt Flutter; React preview không thay Mobile | Giữ Mobile, thay fake bằng dữ liệu thật, đóng gaps/review, inbox announcements stream |
| Một Firestore, không custom server, chỉ dịch vụ trong diagram (p.3) | **Xung đột Web Node/Cloud Run**; Cloud Run bị loại rõ ở hình p.3 | Client SDK + rules/transactions; không Functions/Storage/App Hosting/Run |
| MVVM hai client, shared `packages/core` (pp.3–4; architecture/review 0.5 điểm) | Kotlin/React không chia sẻ Dart trực tiếp | Shared models/Firestore services; theme/widgets theo hình; architecture và review ≥3 findings mới |
| `users/{uid}.role`, Admin bootstrap, chỉ Admin đổi role, deny-default rules, allowed+denied/role/collection (p.4; backend 1.0 điểm) | Agent rules cần viết/test đúng nghiệp vụ, không mặc nhiên đạt | Backend schema/transitions/indexes + emulator matrix; guards cả hai client; không self-promotion |
| App Check Firestore và AI Logic; RC/Analytics cả hai; Crashlytics Mobile (p.4) | Android integration có một phần; Web server Gemini khác AI Logic rubric | Cấu hình từng registration/provider; enforcement metrics, RC before/after, telemetry evidence |
| Web 4 screens + announcement form, queue approve/reject reason, ≥3 aggregate figures + chart, states, Hosting (pp.4–5; Web 2.0 điểm) | React **được cho phép p.5** nếu cùng tokens, nhưng mặc định Cloud Run chưa đạt Hosting | Flutter Web theo phân công; Web owner triển khai và checklist; URL private window ở deadline |
| Cross-role live realtime, 3 runs, latency (pp.2,6,9; integration 1.0 điểm) | Cần backend/role/path giống nhau; gallery multiplayer không chứng minh Firestore sync | PoC rồi flow nghiệp vụ thật, video hai màn, IDs/version/actor/latency và rules evidence |
| ≥1 AI feature qua AI Logic/Gemini Developer API, App Check, RC model/prompt/flag, no PII, editable, graceful fallback (p.5; AI 1.0 điểm) | Web server Gen AI SDK **không đúng đường gọi**; Kotlin AI Logic vẫn sai nền tảng Mobile | Typed JSON → Dart model + user confirmation Level 2; 3 real I/O + 1 failure, analytics events, AI off demo |
| ARTEMIS mọi flow + AI/mobile cross-role, 3 runs; rules tests; Web checklist; AI review mới (pp.5–6; tests 0.5 điểm) | Không tự đạt từ Build verification | Bộ evidence bổ sung; không quy đổi 213 tests thành ARTEMIS hoặc điểm Final |
| Report 10–15 trang, slides 12–15, video live 8–12 phút; repository/history/access/disclosure (pp.6–8; slides/video 2.0 điểm) | Tool không thay deliverables | Team tổng hợp; chốt placeholders `[N]` commits/days với giảng viên; chưa commit trong nghiên cứu |

Rubric Final: hệ thống 8.0 điểm, slides/video 2.0 điểm. B là **phù hợp kiến trúc để triển khai**, chưa phải “đã đạt 10/10”; thiếu cloud/security/AI/E2E evidence vẫn không được coi là đạt. React được phép ở phần Web nhưng shared Dart requirement chưa có ngoại lệ rõ; giữ Flutter Web là hướng ít bất định hơn.

## 7. Các xung đột cần quyết định thay vì tự suy diễn

1. **Storage Lab 3 vs Final:** Lab 3 p.6 yêu cầu upload; Final p.3 chuyển report sang save/share thiết bị + metadata Firestore và loại Storage. Cần nghiệm thu riêng/override bằng văn bản; không đưa Storage vào Final mặc định. Nguồn tài liệu SRS mà Student gửi vẫn phải có contract nội dung hợp lệ, không đẩy file/base64 lớn vào Firestore để lách giới hạn.
2. **FCM:** sơ đồ Final p.3 có “Analytics, FCM, Crashlytics (mobile)”. Vì thế không kết luận Final bỏ FCM. Giữ kế hoạch FCM Lab 3 và inbox Firestore Final là hai phần khác nhau; team chốt sender an toàn không dùng Functions/Run. Client không giữ FCM server credentials; sender/demo console cần thống nhất.
3. **Chiều cross-role:** flow SRS hiện là Student Web nộp → Supervisor Mobile duyệt → Student Web nhận feedback. Final p.4 còn đòi Web queue xử lý item Mobile gửi. Flow SRS chứng minh sync nhưng không tự thay yêu cầu Web queue. Cần giảng viên xác nhận mapping hoặc chọn một nghiệp vụ hiện có phù hợp, không tự đảo vai hay thêm feature chỉ để khớp ví dụ.
4. **AI required vs graceful fallback:** `aiRequiredBeforeSupervisor` có thể khóa bước duyệt khi Gemini lỗi/tắt, trong khi Final p.5 đòi flow vẫn chạy. Nhóm/giảng viên chốt manual/degraded policy và audit, không tự bypass guard hoặc tự approve.
5. **Shared Dart vs React exception:** Final p.5 cho React/Vue cùng tokens, pp.3–4 vẫn yêu cầu shared Dart models/services. Nếu lead muốn React cho bản nộp, cần xác nhận cách đánh giá shared package; chưa có thì giữ Flutter Web.
6. **AI Studio vs Firebase Studio:** là các sản phẩm khác nhau; không lấy khả năng Flutter workspace của một IDE khác làm bằng chứng Build Mode chạy Flutter. [Firebase thông báo hướng công cụ](https://firebase.blog/posts/2026/03/announcing-ai-studio-integration/) không thay tài liệu platform hiện hành.

## 8. Quyết định cần lead/Backend xác nhận

| ID | Quyết định/đầu ra cần chốt | Owner | Chặn bước nào |
|---|---|---|---|
| DEC-01 | Chọn B cho bản Final; AI Studio/Stitch chỉ prototype hay lead cần deliverable demo riêng A? | Lead | Phân bổ công việc/tool sandbox |
| DEC-02 | Project ID, owner/IAM, Spark/Blaze policy, region, database ID, môi trường dev/demo | Backend + Lead | Cloud PoC, không tạo lúc nghiên cứu |
| DEC-03 | Role strings `supervisor/student/admin` hay mapping `staff/user`; Admin bootstrap, assignments, field-level CRUD | Backend + Web + Mobile | Auth/rules/scoped queries |
| DEC-04 | Collection paths, typed DTO/version/revision/time, queries/indexes, allowed transitions/idempotency | Backend chủ trì, hai client ký nhận | Repo adapters và shared core |
| DEC-05 | Duyệt PoC isolated; chọn production cross-role SRS; cách đáp ứng Web queue xử lý item Mobile gửi | Lead + giảng viên + hai clients | Nghiệm thu integration/Web rubric |
| DEC-06 | Lab 3 Storage billing và Final local report; SRS content transport/reader hợp lệ | Lead + Backend + giảng viên | File/export/reader |
| DEC-07 | FCM sender/evidence và announcements producer/audience/read receipts, tránh server keys trong client | Backend + Web + Lead | Push/inbox |
| DEC-08 | AI feature/model được hỗ trợ, free-tier eligibility, JSON schema, PII redaction, RC defaults, fallback/trust policy | AI owner + Backend + Lead | Level 2 và AI-off flow |
| DEC-09 | Play Integrity/Web reCAPTCHA, debug token lifecycle, Auth SHA/domains, enforcement rollout | Backend + Mobile + Web | Real auth/App Check/cloud negative tests |
| DEC-10 | Shared core ownership/versioning/layout, integration vào repo Lab 3 hiện hữu, thời điểm migration | Lead + hai clients | Final structure/MVVM |
| DEC-11 | ARTEMIS model/commit/budget/device, seeds/accounts, latency target, evidence owner; `[N]` lịch sử | QA + Lead + giảng viên | Test/submission evidence |

Đề xuất thứ tự: chốt DEC-01/03/04/05 cho emulator; chỉ khi có quyết định project/billing/attestation mới làm cloud demo; sau khi sync/rules ổn mới gắn AI. Xem [PoC plan](firebase-poc-plan.md). Không có quyết định nào ở bảng này đã được tài liệu nghiên cứu tự phê duyệt thay nhóm.

## 9. Nếu lead muốn thử riêng workflow A

Đây là **test plan tương lai, NOT RUN**, không thực hiện trong task nghiên cứu. Ưu tiên giữ A là prototype so sánh; tránh tiêu thời gian viết lại hệ đã có.

| Bước | Thử nghiệm ở sandbox tách biệt | Bằng chứng/cách đánh giá |
|---|---|---|
| A1 | Dùng một ảnh màn Figma đã duyệt và DESIGN.md không chứa dữ liệu thật làm context Stitch | So token/component/state/navigation trước/sau; ghi rõ nếu chỉ nhập ảnh, không gọi đó là import toàn bộ Figma |
| A2 | Xuất một UI mẫu từ Stitch; thử đường handoff AI Studio được tài liệu mô tả, hoặc source export lưu vào repo mẫu do lead cho phép | Ghi loại output thực tế, framework, files và thao tác thủ công. Không suy ra có Flutter output |
| A3 | Import repo mẫu sạch vào AI Studio; chỉnh một label vô hại rồi thử push/pull trên repo mẫu nếu task sau cho phép GitHub writes | Ghi availability, diff, auth scopes, conflict handling. Không import/push repo chính; không commit ở nghiên cứu hiện tại |
| A4 | Tạo Android native mẫu riêng để kiểm tra platform picker, preview, ZIP và khả năng GitHub trong tài khoản | Đối chiếu Kotlin/Compose với tài liệu; ghi sự khác nhau giữa trang Build và Android. Không lấy APK native thay Flutter APK |
| A5 | Chỉ khi Backend giao sandbox cloud riêng: thử Enable Firebase, xem project/database/location/IAM/rules và Gemini runtime | Review rules trước chia sẻ; chụp config không secrets; xác định Web gọi Gen AI server hay AI Logic. Existing-project integration có thể bị chặn khi đã có Firestore |
| A6 | Nếu lead yêu cầu demo A riêng và cho phép publish: kiểm tra Starter eligibility/billing trước, xác nhận Cloud Run URL/runtime và usage | Prototype có thể PASS chức năng; vẫn FAIL mức phù hợp Final nếu còn Cloud Run/Node hoặc native Mobile thay Flutter. Không gọi publish là Firebase Hosting |

**Điều kiện dừng mở rộng A:** không build được Flutter trong sandbox, không giữ được shared Dart/MVVM, cần Cloud Run cho runtime, hoặc agent integration buộc dùng project khác backend đã chốt. Khi đó lưu kết quả như bằng chứng lựa chọn công cụ và tiếp tục B. Nếu Web React được chọn ngoại lệ, phải có quyết định shared-package và kế hoạch bỏ server/đổi AI Logic/Hosting trước khi đánh giá lại.

Chi phí A phải ghi riêng: số lượt generation/Gemini runtime, Starter hoặc standard Cloud Run usage, Firestore AI shared quota, và thời gian review/mapping lại UI. Chi phí kiểm thử Final còn có ARTEMIS multimodal model calls và thiết bị/thời gian chạy 3 lượt, không gộp thành “Firebase miễn phí”. Tài liệu Lab 3 pp.8–9 yêu cầu model API key; mức tiền cụ thể chốt theo model/tier khi thực thi. Không có ngân sách hoặc account eligibility thì ghi BLOCKED/NOT RUN cho phần cloud A, không bịa demo đã thành công.
