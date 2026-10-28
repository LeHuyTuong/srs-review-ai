# Kế hoạch PoC: Firestore đồng bộ Flutter Web ↔ Flutter Android

Ngày lập/xác minh nguồn: **26/10/2026, Asia/Saigon**. **PLAN ONLY / NOT RUN**: chưa tạo PoC source, Firebase project, app registration, rules deployment, Auth account hoặc AI request. Tất cả tiêu chí PASS dưới đây là dự kiến, không phải kết quả.

## 1. Mục đích và phạm vi tối thiểu

Chứng minh hai client Flutter, đăng ký Android/Web trong cùng Firebase project và trỏ cùng Firestore database, nhận thay đổi bằng realtime listener qua SDK. Đồng thời kiểm tra role rules từ chối thao tác trái phép. Không cần AI Studio để truyền dữ liệu giữa client. Cơ sở: [Firebase projects](https://firebase.google.com/docs/projects/learn-more), [FlutterFire setup](https://firebase.google.com/docs/flutter/setup), [Firestore listeners](https://firebase.google.com/docs/firestore/query-data/listen), xác minh 26/10/2026.

PoC kỹ thuật tách biệt dùng dữ liệu tổng hợp, hai màn: **Web tạo yêu cầu mẫu**, **Mobile Supervisor xem/duyệt hoặc yêu cầu sửa**, Web tự cập nhật kết quả. Có thêm một form Web phát announcement mẫu → Mobile inbox realtime. Mục tiêu chứng minh transport, authorization và lifecycle, không dựng lại toàn hệ SRS hoặc tạo nghiệp vụ mới trong source chính.

Đây là chiều phù hợp SRS hiện tại Student Web → Supervisor Mobile. **Không coi chiều này tự đáp ứng Web review queue ở Final p.4**; quyết định flow nộp Final vẫn cần lead/giảng viên. Nếu cần chiều Mobile submit → Web review, chỉ mô phỏng transport ở sandbox bằng vai trò được phê duyệt, không tự thêm Student Mobile vào sản phẩm.

## 2. Các gate và môi trường

| Giai đoạn | Thiết lập dự kiến sau nghiên cứu | Chứng minh được | Chưa chứng minh |
|---|---|---|---|
| P0: contract | Chốt fields/roles/transitions/queries và expected values, tạo folder PoC riêng | Cùng hiểu dữ liệu và quyền | Chưa có runtime evidence |
| P1: local emulator | Demo project ID `demo-srs-sync`, Auth + Firestore Emulator, 2 Flutter clients | Flutter streams, rules, trạng thái, reconnect, concurrent decisions | Real Google Sign-In, production App Check, Hosting, AI hoặc cloud latency |
| P2: cloud sandbox | Backend cấp một project demo, một Firestore database, Android/Web registrations, Google Auth, App Check; static Web Hosting + APK | Dữ liệu cloud cùng project, auth/attestation, private-window URL, live sync | Toàn bộ features/rubric Final |
| P3: AI mở rộng tùy chọn | AI Logic + RC + schema + fallback trên dữ liệu không PII | Khả năng đạt Level 2 của feature được chọn | Không thay đồng bộ/rules tests; không phải phần bắt buộc của PoC sync tối thiểu |

Mọi phase thực thi là công việc tương lai được nhóm giao riêng. Trong nghiên cứu này không chạy kể cả P1. PoC dự kiến ở directory/repo riêng do lead chọn, không khởi tạo SDK trong `D:/SRS-Review-AI-Mobile` hoặc `D:/UI AI Review`.

P1 không cần Firebase project thật: dùng ID prefix `demo-`, khởi chạy đúng Auth/Firestore emulators. Cả CLI, Auth và hai clients dùng cùng demo project ID; endpoint được cấu hình bắt buộc, nếu thiếu thì **fail khởi động**, không fallback cloud. [Demo projects/emulator](https://firebase.google.com/docs/emulator-suite/connect_firestore).

## 3. Kiến trúc PoC đề xuất

```text
isolated-poc/                 # thư mục dự kiến, chưa tạo
  packages/core/             # DTO models, codecs, repo contracts, Firestore services
  mobile/                    # Flutter Android Supervisor + MVVM/Riverpod
  web/                       # Flutter Web Student/Admin + MVVM/Riverpod
  firebase/                  # rules, indexes, emulator config, rules tests
  evidence/                  # runs, screenshots/video, logs đã khử PII
```

`View → VM → Repository → Firestore/Auth service`. Streams và commands nằm dưới VM; VM quản loading/empty/error/data, draft/pending/conflict/retry. DTO converter không để `Timestamp`/`DocumentSnapshot` tràn vào View. Hai client share models/services cùng version; platform Auth/App Check configuration nằm ở composition root mỗi app. [Flutter MVVM](https://docs.flutter.dev/app-architecture/guide), [testing recommendations](https://docs.flutter.dev/app-architecture/recommendations).

P1 dependencies dự kiến: `firebase_core`, `firebase_auth`, `cloud_firestore`, Riverpod. P2 thêm `firebase_app_check`, Google sign-in integration phù hợp từng nền tảng. P3 thêm `firebase_ai`, `firebase_remote_config`, `firebase_analytics`; Crashlytics Mobile ở giai đoạn Final riêng. Chọn/pin versions khi thực thi dựa vào SDK compatibility, không sửa manifest chính ở nghiên cứu.

## 4. Contract dữ liệu mẫu, chưa phải schema production

PoC dùng collections `pocRequests` và `announcements` chỉ trong project/emulator riêng; không ghi lên collections SRS production. Giới hạn dữ liệu mẫu nhỏ (title ≤120 ký tự, reason ≤500, ≤20 records mỗi query). Thống nhất database ID `(default)` cho P1/P2 nếu Backend không chọn khác; nếu dùng named database phải truyền đúng ID cho cả hai apps và emulator/rules tests.

| Path | Fields tối thiểu / type | Quyền và invariants đề xuất |
|---|---|---|
| `users/{uid}` | `role: student/supervisor/admin`; profile Student có `assignedSupervisorUid:string` | Owner đọc profile; Admin quản role/assignment của PoC. Seed initial Admin ngoài client. Không self-promote, không tự chọn Supervisor ở login |
| `pocRequests/{requestId}` | `studentUid:string`, `supervisorUid:string`, `title:string`, `status:pending/approved/needsRevision`, `reason:string`, `revision:int`, `commandId:string`, `createdAt/updatedAt:timestamp` | Student tạo own request `pending`, revision=0, supervisor assignment hợp lệ; chỉ owner/assigned supervisor đọc; Supervisor chỉ quyết định request assigned khi pending, revision tăng đúng 1; identity/assignment/createdAt bất biến; terminal không ghi lại |
| `announcements/{announcementId}` | `title/body:string` bounded, `targetUid:string`, `status:published`, `createdBy:string`, `createdAt:timestamp` | Admin Web tạo cho UID được chọn trong PoC; chỉ target và Admin đọc; deny client update/delete cho PoC. Đây là simplification, audience/archival production phải chốt riêng |

P1 seed tối thiểu: `student-a`, `supervisor-a`, `supervisor-b` (outsider), `admin-a`, hai requests, một announcement. Khi Student tạo request, rules yêu cầu `supervisorUid == users/{studentUid}.assignedSupervisorUid` và profile người nhận có role Supervisor; Student không được sửa assignment để vượt scope. Assignment PoC giữ cố định trong mỗi run; role/assignment revocation giữa phiên là test mở rộng trước production. P2 thay bằng Auth UID thật và fixture tổng hợp; không dùng literal fake UID làm bằng chứng authentication.

Rules deny-default, allowlist fields/types/length/enums; validate `createdAt/updatedAt` bằng server time policy và field diffs. Query có filter đúng scope (`studentUid==uid` hoặc `supervisorUid==uid`), sort/limit/index đã chốt. Rules không là bộ lọc thay client query. Backend viết/test rules cụ thể trước khi chạy app; không dùng `allow read, write: if true`. [Rules/Auth](https://firebase.google.com/docs/rules/rules-and-auth), [Rules tests](https://firebase.google.com/docs/rules/unit-tests).

Command decision: transaction đọc document → kiểm tra assigned actor, expectedRevision/status → update `status/reason/revision/updatedAt/commandId`. Callback transaction có thể chạy nhiều lần; không gửi Analytics hoặc sửa UI state trong callback. Double tap bị khóa ở VM; retry dùng cùng commandId, không tạo decision thứ hai. Rules phải kiểm tra invariants độc lập, không tin client guard. Hai reviewer race chỉ một update terminal thắng; người còn lại thấy conflict. Transaction offline báo chưa gửi và giữ draft; không hiện “đã duyệt”. [Transactions](https://firebase.google.com/docs/firestore/manage-data/transactions).

## 5. Trình tự thử nghiệm dự kiến

### P0 — chuẩn bị và baseline

1. Lead ký nhận phạm vi PoC, owner Web/Mobile/Backend/QA và flow kỹ thuật. Chốt role strings/assignment/time/indexes/latency target. Chốt việc PoC không phải full Final acceptance.
2. Chụp baseline checksum source chính và lưu trạng thái tests đã có; PoC nằm riêng. Tài liệu Phase 5.0 là bằng chứng 213 PASS lịch sử, không chạy lại và đổi nhãn trong nghiên cứu này.
3. Pin Flutter/Dart, FlutterFire, Firebase CLI, Java tương thích emulator, Node và rules-unit-testing. Ghi OS/device/browser/versions. Tài liệu emulator cảnh báo yêu cầu Java 21 sắp tới; kiểm tra release cụ thể khi cài, không mặc định Java cũ đủ.

### P1 — local không cloud

4. Tạo PoC Flutter tối thiểu hai entrypoints/apps và shared package theo §3. Chỉ dùng demo Firebase options; không chạy configure để tự tạo cloud project. Firestore settings/emulator connection đặt trước operation đầu tiên.
5. Khởi chạy Auth/Firestore Emulator cùng `demo-srs-sync`; seed qua test harness tin cậy. Nạp `firestore.rules` rõ ràng và negative control trước UI test, tránh emulator vô tình open rules.
6. Web browser trên host dùng localhost, Android emulator chuẩn dùng `10.0.2.2` về host; điện thoại thật dùng IP LAN của host nếu sau này cần, bind/firewall chỉ trong mạng test. Android HTTP/cleartext exception chỉ ở debug PoC nếu cần. Không đưa config emulator/debug vào release.
7. Auth Emulator dùng identity test local; test này không chứng minh account picker Google thật. Rules tests dùng v9 `initializeTestEnvironment`, `authenticatedContext`, `unauthenticatedContext`, `assertSucceeds/assertFails`; chỉ seed setup được bypass rules. UI operations dùng client SDK với auth, không Admin SDK. [Rules API](https://firebase.google.com/docs/rules/unit-tests).
8. Web Student tạo request có run ID duy nhất. Mobile Supervisor mở stream scoped, thấy đúng title/status/revision; không refresh thủ công. Mobile quyết định, Web listener hiển thị terminal state/reason/revision mới. Chạy đủ ba lượt với records sạch.
9. Web Admin publish announcement cho Supervisor; Mobile inbox nhận mới bằng listener. Không dùng FCM để giả lập realtime Firestore; push lifecycle là hạng mục riêng của Lab 3/Final.
10. Chạy tests sai quyền, malformed data, query scope, offline/reconnect, double-submit/race, logout/switch account. Phân biệt cache/local pending và backend state, lưu cả failure nếu có.

### P2 — cloud demo sau khi được nhóm giao thực thi

11. Backend cung cấp/cho phép tạo sandbox riêng, chọn region/database ID trước tạo. Đăng ký Android/Web cùng project, cấu hình FlutterFire đúng hai apps. Không dùng auto-provision AI Studio vào project chính; limitation existing Firestore không ảnh hưởng SDK route B.
12. Bật Google Auth; cấu hình Android signing SHA/package và authorized Web domains. Bootstrap Admin và role/assignment bằng cơ chế Backend quản; tester không tự cấp role. Kiểm tra sign-in cancel/wrong role/missing profile.
13. Đăng ký App Check cho cả apps (Flutter Android Play Integrity, Web reCAPTCHA theo support đã chọn); debug provider chỉ test có kiểm soát. Bật enforcement Firestore sau khi tokens hợp lệ; AI Logic workflow mới có thể tự enforce từ setup, phải kiểm tra console. Không để `disabled` rồi kết luận đạt security. [Flutter App Check](https://firebase.google.com/docs/app-check/flutter/default-providers), [AI Logic setup](https://firebase.google.com/docs/ai-logic/get-started).
14. Backend deploy rules/indexes đã test; Web owner build static release và Hosting, Mobile owner tạo APK PoC. Không Functions/Run/App Hosting/Storage. URL mở được trong cửa sổ private; đăng nhập demo đúng role trước xem protected data.
15. Lặp TC-01..TC-10 trên cloud ở §6; App Check TC-10 chỉ xác nhận bằng cloud. Quay hai màn đồng thời và ghi project ID/database ID/app IDs, request ID, run ID, revision, metadata và timings. Không ghi passwords/debug tokens.

### P3 — mở rộng AI, không chặn sync PoC

16. Chốt một input SRS tổng hợp đã khử PII, chọn model khả dụng cho tier của project, bật Gemini Developer API qua AI Logic. Không hard-code raw Gemini key trong client. RC `ai_enabled/model/prompt` có defaults và validation; startup App Check trước AI calls.
17. Gọi qua injected AI service, response JSON schema → model Dart, label AI/edit/accept; không tự approve. Run ba real inputs/outputs + một lỗi network/quota hoặc AI-off theo rubric. Invalid JSON/IDs bị reject/retry; người dùng giữ draft và tiếp tục manual nếu policy được duyệt.
18. Kiểm tra RC tắt AI không cần rebuild; đúng events `ai_request`, `ai_result_accepted`, `ai_error`, không PII. Đo riêng latency AI, không gộp vào latency Firestore. P1 emulator không mô phỏng đầy đủ Gemini/App Check/RC/Analytics; P3 cần dịch vụ thật hoặc mock có ghi rõ giới hạn.

Nguồn kiến trúc/thực thi: [Flutter setup](https://firebase.google.com/docs/flutter/setup), [Emulator](https://firebase.google.com/docs/emulator-suite/connect_firestore), [Hosting](https://firebase.google.com/docs/hosting), [AI Logic Dart](https://firebase.google.com/docs/ai-logic/get-started), [Structured output](https://firebase.google.com/docs/ai-logic/generate-structured-output). Tất cả xác minh 26/10/2026.

## 6. Ma trận đánh giá

| ID | Thử nghiệm | Điều kiện PASS dự kiến | Evidence | Trạng thái hiện tại |
|---|---|---|---|---|
| TC-01 | Web create → Mobile observe | Cùng ID/title/pending/revision=0, không refresh, server xác nhận | Video 2 màn + log run/project/database + metadata | NOT RUN |
| TC-02 | Mobile decide → Web observe | Status/reason đúng, revision=1, đúng actor, không duplicate | Before/after, server readback, timings; 3/3 runs | NOT RUN |
| TC-03 | Web announcement → Mobile inbox | Chỉ target thấy đúng announcement mới, một item/ID | 2 màn + document ID/audience query | NOT RUN |
| TC-04 | Sai role/scope/unauth | Student approve, outsider read/write, self-promote, wrong-role client đều bị chặn; document không đổi | Rules test allowed/denied + UI recovery; kiểm tra server state | NOT RUN |
| TC-05 | Shape/transition/query | Thiếu field, unknown enum, đổi owner/assignment, nhảy revision, terminal rewrite, broad query đều bị deny; valid scoped query pass | Emulator assertions + trace | NOT RUN |
| TC-06 | Offline/reconnect | Hiện cached/offline; decision transaction không báo success khi offline; reconnect thấy latest server state, draft không mất | Network timeline + server revision + retry | NOT RUN |
| TC-07 | Race/double-submit | Một terminal transition, một revision tăng; lệnh còn lại conflict/idempotent, không hai kết quả chính thức | Hai phiên Supervisor được assign cùng actor test, command IDs + final state | NOT RUN |
| TC-08 | Logout/switch account | Listener cũ detach; UI cũ không xuất hiện với tài khoản mới; quyền server vẫn deny cross-user | Video đổi tài khoản + listener count/state assertions | NOT RUN |
| TC-09 | Persistence và deployed Web | Reload browser/restart Android online vẫn thấy server data đúng; URL private window tải được và auth đúng | APK/build ID, URL, screenshots + server read | NOT RUN |
| TC-10 | Cloud App Check | Client đã attest gọi được; request có Auth nhưng thiếu/invalid App Check bị chặn ở enforcement; không nhầm lỗi rules thành App Check | Console enforcement/metrics + controlled negative request | NOT RUN |
| TC-AI | AI tùy chọn | Typed output/edit/accept, 3 I/O thật, failure/RC off có fallback đúng policy, events không PII | AI doc/config version + UI/event evidence | NOT RUN |

Với mỗi collection PoC, rules suite phải có ít nhất một allowed và một denied case cho từng role, cùng unauth tests. Không cố tạo allowed write cho role bị cấm toàn bộ: chọn allowed operation phù hợp (ví dụ own-profile read) và ghi N/A có lý do cho operations không cấp quyền. Với role không có bất kỳ allowed operation trên collection đó, ghi **intentionally denied-all**, test mọi operation bị cấm và xin QA/giảng viên chấp nhận cách diễn đạt matrix; không nới rules chỉ để đủ dòng allowed. Khi mở rộng Final, lặp ma trận cho toàn bộ production collections, không chỉ ba paths PoC.

## 7. Đo realtime và tiêu chí chấp nhận

Không coi local optimistic snapshot là đồng bộ xuyên thiết bị. Subscribe metadata changes và ghi `hasPendingWrites`, `isFromCache`; chỉ đánh dấu server observation khi không còn pending/cache phù hợp SDK. Receiver phải thấy cùng commandId/revision trên client khác; có server readback để đối chứng. [Realtime metadata](https://firebase.google.com/docs/firestore/query-data/listen), [Offline](https://firebase.google.com/docs/firestore/manage-data/enable-offline).

Đo ba thời điểm: T0 người dùng gửi lệnh, T1 writer được server xác nhận, T2 receiver render revision tương ứng. Receiver có thể cập nhật trước writer nhận ACK, vì vậy không lấy `T2−T1` làm latency bắt buộc không âm. Dùng `T2−T0` làm user-perceived latency và `T1−T0` làm write-ack latency.

Ưu tiên quay hai màn trên **cùng timeline video/host monotonic clock** (Android mirror + browser) để tránh trừ đồng hồ hai thiết bị chưa đồng bộ. Nếu dùng timestamp trên hai máy, báo clock offset/uncertainty; `serverTimestamp` không tự giải quyết phép đo thời điểm render. Lưu từng mẫu; với chỉ 3 mẫu báo min/median/max, không quảng cáo p95 ổn định.

Mục tiêu đề xuất do nhóm duyệt, **không phải SLA Firebase hoặc ngưỡng của giảng viên**: mỗi hướng online thấy dữ liệu trong ≤3 giây trên mạng demo ổn định; timeout quan sát 10 giây ghi FAIL và điều tra, không xóa ca chậm. Cross-role cloud ba lượt phải **3/3 đúng giá trị**, rules suite 100% expected allowed/denied, không lỗi role leak/duplicate/false success. Nếu đúng dữ liệu nhưng chậm mục tiêu, báo correctness PASS/latency FAIL riêng.

Record mẫu:

```text
run_id | environment | builds/SDK versions | project_id/database_id
actor role | request_id | command_id | revision_before/after
T0/T1/T2 (same timeline) | ack_ms | observed_ms | metadata
expected | actual | pass/fail/not_run | evidence_path | failure_reason
```

**PoC acceptance:** P1 pass chỉ cho phép kết luận local SDK/rules flow hoạt động; P2 pass mới cho phép kết luận Web/Mobile sync trên Firebase thật. TC-10 không thể pass từ emulator. PoC pass không thay ≥10 ARTEMIS Lab 3, toàn bộ Final cross-role nghiệp vụ, Web checklist, code review hoặc regression Mobile.

## 8. Chi phí, giới hạn và rủi ro

| Hạng mục | Dự toán/giới hạn đề xuất | Rủi ro và xử lý |
|---|---|---|
| P1 local | Không gọi cloud, không cần billing; chi phí máy/thời gian | Endpoint sai có thể gọi cloud nếu dùng real config. Dùng `demo-` ID, bắt buộc endpoint và fail khi thiếu |
| P2 Firestore | Hướng tới $0 trong Spark quota; bộ PoC ≤20 docs/query, 3 lượt acceptance, không load toàn database | Standard free quota 50k reads/20k writes/20k deletes/ngày, 1 GiB storage; rules reads/listener/reconnect tính thêm. Theo dõi usage trước/sau, đóng listeners sau test |
| Hosting/Auth/App Check | Dùng mức no-cost/quotas hiện hành phù hợp phương thức và provider; chưa có báo giá account-specific | Không bảo đảm mọi provider/volume miễn phí. Chốt region/domains, kiểm tra usage/attestation và quota trước demo |
| AI optional | Chỉ 3 input thật + 1 failure, giới hạn input/output, tránh auto retry vô hạn; model/tier quyết định giá | AI Logic miễn phí lớp dịch vụ, Gemini có quota/paid costs. Model có thể đổi/quota thấp; RC chọn model hợp lệ/fallback, không hứa tên model tutorial còn chạy |
| Blaze nếu được duyệt | Chưa chọn budget USD, owner và caps nên **chưa cho phép bật billing trong kế hoạch thực thi** | Alerts không hard stop. Đặt budget cảnh báo/quota/spend caps tương ứng, chốt quyền bật/tắt và theo dõi cost; không tự upgrade |
| AI Studio A tùy chọn | Repo mẫu + dữ liệu tổng hợp, kiểm tra Starter eligibility; tiêu tốn AI/GitHub/cloud usage nếu thực thi | Không import source chính, không cho agent sở hữu rules project chính; rules overwrite/IAM/location/database limitation |
| Lab 3 Storage | Không có trong PoC hoặc Final B | Storage hiện cần Blaze, khác ghi chú Spark của đề; lead/giảng viên quyết định nghiệm thu riêng |

Cơ sở xác minh 26/10/2026: [Firestore quota](https://firebase.google.com/docs/firestore/quotas), [AI Logic pricing](https://firebase.google.com/docs/ai-logic/pricing), [AI Studio shared quota](https://firebase.google.com/docs/ai-assistance/ai-studio-integration), [AI Studio deploy tiers](https://ai.google.dev/gemini-api/docs/aistudio-deploying), [Storage billing](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024).

Nếu cần ước tính trả phí trước P3: `AI_cost ≈ requests × (avg_input_tokens × input_rate + avg_output_tokens × output_rate) / 1.000.000`, cộng tính năng bổ sung nếu dùng. Firestore/Hosting/Auth/attestation tính riêng theo usage/region/free allowances. Đây là công thức dự toán, không phải báo giá; điền rates từ model/provider được chốt ngay trước thử nghiệm.

Rủi ro cần test thêm khi tích hợp sản phẩm: cache nhạy cảm còn lại sau logout; pending write đã gửi không thể thu hồi chỉ bằng token local; transaction không thay rules; role đổi giữa session; query/index cloud khác emulator; AI output do client ghi có thể giả mạo; file SRS và PII chưa có transport/redaction policy. Chưa giải quyết các điểm này thì không mở rộng PoC thành production adapter.

## 9. Người phụ trách, quyết định và đầu ra sau PoC

| Owner | Cần xác nhận trước thực thi | Đầu ra mong đợi |
|---|---|---|
| Lead + giảng viên | B là main; flow SRS có đáp ứng Web queue/cross-role không; Storage/FCM/AI fallback/shared package interpretation | Decision record, phạm vi nghiệm thu |
| Backend | Project/region/database/billing owner, roles/assignments, schema/rules/indexes, seed/admin bootstrap, App Check enforcement | Contract + rules test report + config checklist |
| Web owner | Client Flutter Web, tokens, Google Auth, scoped listeners, Hosting, announcement role | Build/URL + checklist và evidence |
| Mobile owner | PoC riêng Supervisor, giữ source/213-test baseline, auth/stream/transaction cleanup | APK PoC + VM/repo tests, integration evidence |
| AI owner | Model/tier/schema/PII/RC/fallback, không raw key | 3 real I/O + failure/config evidence nếu làm P3 |
| QA | Device/browser/tool versions, expected seed values, latency target và timelines, ARTEMIS phase sau | Test matrix từng run, logs/video, defect decisions |

Chi tiết quyết định ở [DEC-01..DEC-11](workflow-comparison.md#8-quyết-định-cần-leadbackend-xác-nhận). Chưa có project/billing authorization thì vẫn có thể lập contract và thực hiện emulator ở task triển khai riêng; không cần dừng toàn bộ công việc để chờ cloud.

Sau PoC, bàn giao report ghi PASS/FAIL/NOT RUN theo từng môi trường, links evidence và hạn chế; đề xuất thứ tự tích hợp Auth → scoped realtime read → typed transactions → inbox → AI/telemetry → Final E2E. Chỉ chuyển adapters sang Mobile chính khi contracts đã ký nhận và có kế hoạch regression đầy đủ; không copy toàn snapshot fixture vào Firestore.

Khi đóng PoC, unsubscribe listeners, sign out demo sessions, revoke debug tokens, ghi usage/cost cuối và lưu evidence an toàn. Việc unpublish/xóa tài nguyên sandbox phải do owner quyết định ở task thực thi, không xóa project dữ liệu dùng chung. **Nghiên cứu hiện tại kết thúc ở ba tài liệu; toàn bộ chạy thử vẫn NOT RUN.**
