# Phase 5.0 - Supervisor Mobile readiness và roadmap

Ngày: **26/10/2026 (Asia/Saigon)**. Phạm vi cá nhân: **Flutter Android Supervisor/Giảng viên** tại `D:/SRS-Review-AI-Mobile`. Web và Firebase Backend do thành viên khác phụ trách. `D:/UI AI Review` chỉ đọc. Tài liệu này là kế hoạch các phase sau, **không phải ủy quyền tự động bắt đầu triển khai trong 5.0**.

## 1. Kết luận readiness

**Đã có nền tảng local để tiếp tục thiết kế contract, chưa sẵn sàng chuyển cả FakeAcademicService sang Firebase.** MVVM/Riverpod/DI, UI routes Supervisor và 213 regression tests được giữ. Phase 4.5 đã sửa search focus, session isolation local, Course identity/uniqueness, Project detach/Class fallback, Dashboard semester preservation và các projections A01 cụ thể.

**Còn thiếu:** Google auth/verified role, scoped Firestore queries/transactions/listeners, DTO cho phần ngoài Course, reader tài liệu thật, realtime inbox, report export, AI Logic, RC/analytics/crash, ARTEMIS, cross-role deployed evidence. AUD-A03 vẫn PARTIAL; notification filtering/unread aggregation còn trong View. Không lấy UI fake hoặc 213 tests để tuyên bố hoàn thành Lab 3/Final.

Bốn tài liệu đầu ra:

- [Grading compliance và screen/flow RTM](mobile-grading-compliance.md): các yêu cầu đã có, thiếu, ngoài phạm vi và khác biệt Lab 3/Final.
- [Firebase/DTO/repository contracts draft](mobile-firebase-contracts.md): schema, status, transaction, quyền và DEP-01..12 cần nhóm thống nhất.
- [Test Coverage Matrix](mobile-test-coverage.md): 213 tests hiện có, integration plans, ARTEMIS draft và quy tắc evidence.
- Roadmap này: thứ tự migration, owner/dependency và gate nghiệm thu.

## 2. Không được tự quyết thay nhóm

| Quyết định mở | Cần ai xác nhận | Hệ quả trước khi có xác nhận |
|---|---|---|
| Lab 3 Storage/FCM vs Final service limits; PDF local/share + metadata | Nhóm + giảng viên | Không cài Storage/FCM tùy ý hoặc bỏ tiêu chí Lab 3; ghi hai checklist riêng |
| Student Web -> Supervisor Mobile là F3 cross-role; Final Web queue phải xử lý Mobile-submitted item nào | Nhóm + giảng viên | Giữ F3 hiện hành làm ứng viên; chưa tuyên bố Final cross-role/Web review queue hoàn tất |
| Role strings/assignments và ai quản lý catalog/global rule/registration | Backend + Web + Mobile | Không cấp Supervisor mọi quyền từ fake UI, không alias role staff/admin thành Supervisor ngầm |
| File source cho submission/reader không dùng Storage trong Final | Nhóm + giảng viên | Reader/F3 gate chưa mở; không dùng sample reader làm bằng chứng real file |
| AI-required rule khi AI bị tắt/lỗi và trust model client AI | Nhóm + giảng viên/Backend | Không tự bypass guard; giữ draft, retry/blocked rõ ràng cho tới khi policy cho manual |
| Shared core package/API ownership | Nhóm | Chỉ chốt DTO/contracts thuần Dart hiện tại; không tạo monorepo hoặc move project |

## 3. Các phase đề xuất và điều kiện hoàn thành

| Phase đề xuất | Mobile thực hiện khi được chuyển phase | Dependency / owner khác | Exit gate có thể kiểm chứng |
|---|---|---|---|
| **5.0 - Audit/docs (hiện tại)** | Đối chiếu rubric/source, screen+flow RTM, contract/test matrix, roadmap | Chưa cần cấu hình backend | Đủ 4 docs; không sửa source/React/Firebase; baseline 213 giữ nguyên |
| **5.1 - Contract review và scope sign-off** | Gửi nhu cầu query/commands, DTO và error taxonomy; review policy/file/status/roles | DEP-01..12, Backend/Web/giảng viên; nhóm thống nhất người chịu trách nhiệm và quyết định | Schema/permissions/status/query/index/seed/version/idempotency có mẫu và chữ ký/biên bản quyết định; file và cross-role được chấp thuận |
| **5.2 - Typed boundaries trên fake** | Tách DTO/codec và repository slices theo ưu tiên Course -> Review -> class/group/project; thêm conformance tests; tách Notifications VM/empty state; chuẩn bị injected auth/config/telemetry interfaces | Contract accepted; chưa cần bật Firebase cho toàn app | Fake chạy cùng contract tests; 213 regression còn đủ; không whole-snapshot API mới; invalid DTO/unknown enum/time/permission errors xử lý rõ |
| **5.3 - Auth và Course vertical slice** | Sau khi có project/config từ team: Google auth -> role/assignment -> session mapping; Course list/get/typed create/update transaction adapter qua DI | Backend cấp env/demo accounts/rules/code index/emulator tests (DEP-01/02/03/09/10) | Verified UID/role; wrong role/cancel/offline/denied; A->logout->B/callback/cache; two-client Course code race một success; không upload AcademicSnapshot |
| **5.4 - F1 academic/group/project** | Scoped queries/paging/subscriptions, typed roster/group/project commands và Dashboard projection; chuyển từng route sang Firebase | Backend invariants/indexes; Web catalog/roster data theo ownership | F1 happy/alternate/error trên data thật; enrollment/project liên kết atomic; overrides/history không mất; filter selection và detach invariants còn đúng |
| **5.5 - F2 và Supervisor slice F3** | Real reader theo file contract; queue/workspace/version/feedback/decision adapters; version-bound transaction và stream disposal | Web tạo v1/v2 cùng reviewId; Backend rules/schema/notification strategy (DEP-04/05/06/07) | v1 needsRevision -> v2 approved; v1 feedback/history nguyên vẹn; stale/two-reviewer/duplicate command safe; Mobile không nộp file thay Student |
| **5.6 - Inbox/export/AI/instrumentation** | Inbox realtime/read receipt/deep link; PDF local/share+metadata; AI Logic JSON/edit/accept; RC defaults/flag/model/prompt; analytics/crash và Firebase demo area | Web announcements; Backend App Check/RC/rules/console setup; file/FCM/Storage decisions | Inbox đúng audience; AI labeled/no PII/fallback; ≥2 RC behavior params; ≥7 events DebugView; nonfatal+crash evidence; report đúng scope. Lab 3 upload/FCM có checklist riêng nếu cần |
| **5.7 - Joint verification & evidence** | Giữ regression; Flutter adapter/device integrations, ARTEMIS ≥10 cases/≥3 runs, Pro exploratory, UX/a11y; hỗ trợ quay Mobile demo | Backend rules all pass; Web checklist/deployment; 3 cross-role deployed runs | RTM gaps đóng bằng evidence thật; test report có pass rates/traces/flaky causes, real AI 3 inputs/outputs + failure; ≥3 Final review findings có quyết định |
| **Handoff Final** | Bàn giao Mobile models/contracts/docs/evidence; hỗ trợ nhóm dùng shared package sau | Nhóm sở hữu packages/core, cấu trúc repo, Web Hosting và submissions | Shared package/MVVM criterion được chứng minh trên hai clients; README/report/slides/video accessible; không đổi cấu trúc local ở 5.0 |

5.6 có thể chia nhỏ, chỉ làm phần không phụ thuộc sau khi contract tương ứng đóng. Không cần đợi mọi dịch vụ xong mới kiểm thử một vertical slice; cũng không bỏ gate auth/rules/DTO để nối Firestore cả snapshot cho nhanh.

## 4. Cách thay FakeAcademicService từng bước

1. **Đóng băng invariants**, không đóng băng raw snapshot API làm backend API. Lập shared conformance tests cho ID/code, membership/project links, immutable version/rule/feedback/history, revision conflict, session revoke và error mapping. Giữ fake/fixtures dùng cho unit/widget tests; submitted build phải dùng real data theo rubric.
2. **Tách read/write contracts**. Queries typed theo scope/semester/class, page/cursor/stream; commands theo workflow và expected entity revision/versionId. Course seam có sẵn là điểm bắt đầu nhưng đổi return type sang entity/receipt khi migration, không trả toàn kho.
3. **Đưa DTO codec vào data boundary**, giữ domain/policy thuần Dart. Mapping Timestamp -> UTC model/date-only; actor -> UID; enum có lỗi invalidData; update chỉ fields được phép. Không preserve unknown fields rồi gửi ngược các field nhạy cảm lên server.
4. **Cài adapter theo DI sau contract sign-off**. `academicServiceProvider` fake vẫn cho test; app production wiring chuyển từng repository slice. Query errors/loading/empty/retry và subscriptions do VM quản lý. Nếu cần snapshot facade tạm cho legacy View thì phải chỉ chứa dữ liệu đã được authorized và không có đường commit whole-snapshot vào Firestore.
5. **Khóa auth/session trước dữ liệu người dùng**. Auth-state + verified role/assignment tạo SessionScope/generation mới; scope không phải credential. Hủy listeners/revoke callback/navigation/draft ngay khi logout/role revoke. Xử lý persistent cache/pending writes theo policy thống nhất, không xóa backend committed data.
6. **Chuyển Course trước**, transaction Course+normalized-code reservation+revision. Hai clients cùng tạo/đổi code phải chỉ một lệnh hợp lệ; code collision không thành upsert; legacy references không đổi ID.
7. **Chuyển class/group/project theo atomic commands**, không lần lượt ghi documents rồi vá quan hệ ở UI. Validate capacity/membership/assignment/single-active-project bằng rules+transaction; scopes bounded; query/index đáp ứng All/filter UI hoặc có deviation đã ghi.
8. **Chuyển Review theo version**, decision receipt chỉ success sau server acknowledgment; official feedback/audit/notification consistency theo contract. AI stale result chỉ lịch sử; không cập nhật current version sai. Không log Student submission note như Supervisor decision note.
9. **Chạy song song kiểm chứng có kiểm soát**, so các query/projections trên cùng seed; không double-write fake+Firebase hoặc âm thầm lấy fake fallback khi backend denied/offline. Data source rõ trong test harness; build nộp không hiển thị fixture như real data.
10. **Loại legacy write path từng workflow** khi conformance, emulator/rules và device tests pass. Chỉ loại fake wiring khỏi build nộp sau khi tất cả routes dữ liệu thật; giữ fake adapters cho tests. Không xóa regression để đạt migration gate.

Rollback của một slice là đổi lại DI trong môi trường dev/test và giữ schema/data đã tạo theo plan của nhóm; không tự xóa Firestore hoặc overwrite cloud bằng fixture. Migration schema/seed là công việc Backend có review; Mobile chỉ mapping đọc/ghi contract đã chốt.

## 5. Cross-role candidate F3: phần Mobile phải làm

Candidate bám `D:/UI AI Review/ux/user-flow.md` Phần A. Cần DEP-07 sign-off vì ví dụ/rubric Web queue Final có hướng phê duyệt khác; **không khẳng định candidate tự đáp ứng mọi yêu cầu Web**.

| Step | Actor/client/screen | Data interaction dự kiến | Mobile phải thực hiện / rule và evidence cần |
|---|---|---|---|
| XR-01 | Student Web Documents/Upload v1 | Create DocumentVersion v1 + logical ReviewRequest waiting, currentVersionId=v1 | Web/Backend làm; Mobile không upload. Rule owner/membership/duplicate submit; team cung cấp seed/commit ID |
| XR-02 | Supervisor Mobile Review queue | Scoped stream reviewRequests theo assignment | Hiện request mới khi server cập nhật, mở đúng reviewId/v1; deny lớp ngoài quyền; đo latency Web write -> Mobile render |
| XR-03 | Supervisor Mobile Workspace/AI | Read version/rule snapshot, draft feedback; AI theo policy | Reader thật; đúng document/version; labeled findings; user edit/select; AI error không mất draft; không auto approve |
| XR-04 | Supervisor Mobile confirm needsRevision | Transaction request+decision+official feedback+audit+notification theo contract | actorUid, expectedVersionId/revision, commandId; chỉ feedback v1 được official; success sau ack; conflict giữ draft |
| XR-05 | Student Web feedback/inbox | Read official v1 feedback/status/notification | Web làm UI; Mobile kiểm history v1 vẫn có. Đo latency Mobile ack -> Web render; không xem static notification là proof |
| XR-06 | Student Web sửa/nộp v2 | Append version v2, update currentVersionId, needsRevision->waiting, giữ reviewId | Web/Backend validate file/status; Mobile stream chuyển về v2, draft/AI binding không dính v1; giữ v1 immutable |
| XR-07 | Supervisor Mobile review v2 -> approved | Decision transaction cho v2, selected feedback/version binding | Kiểm AI-required/new evaluation nếu policy cần; duyệt đúng v2; không ghi đè feedback/AI/audit v1 |
| XR-08 | Student Web result; Supervisor Mobile history/inbox | Web đọc approved v2, cả hai đọc history được quyền | Xác nhận reviewId không đổi, version IDs khác, history đầy đủ; 3 deployed runs có runId/trace/time |
| XR-09 | Web staff announcement form -> Mobile inbox | Publish announcements đúng audience; Mobile query realtime + own receipt | Nhận/mở/markRead bền vững, auth-gated route; sai audience không thấy. Đây là Final inbox evidence bổ sung, không thay vòng F3 |

```mermaid
sequenceDiagram
    participant W as Student Web
    participant F as Shared Firestore (Rules)
    participant M as Supervisor Mobile
    W->>F: Submit v1 + ReviewRequest R (waiting)
    F-->>M: Scoped queue stream: R / v1
    M->>F: decide(R,v1,needsRevision,feedback,expectedRevision,commandId)
    F-->>W: Official feedback v1 + status/inbox
    W->>F: Append v2, same R, set waiting
    F-->>M: Current version v2; preserve v1 history
    M->>F: decide(R,v2,approved,expectedRevision,commandId)
    F-->>W: Approved v2 + history
```

Đây là sequence **dự kiến sau tích hợp**, chưa có event thật. Nếu group/assignment bị revoke, version đổi khi đang mở, hai Supervisor quyết định, network mất sau gửi hoặc command retry: phải xử lý conflict/ack/idempotency theo contract. Không tự tạo flow mới Mobile submit -> Web approve khi nhóm chưa chọn nghiệp vụ phù hợp.

## 6. Yêu cầu hỗ trợ từ Web và Backend

| Bên nhận | Deliverable nhóm cần cung cấp | Mobile sẽ bàn giao/kiểm tra |
|---|---|---|
| Backend | Schema fields/types/path/version, CRUD/transition matrix theo role, assignments, index/query constraints và seed mapping | DTO nhu cầu, repository method draft, domain invariants và conflict/error UI expectations |
| Backend | Rules deny-by-default, shape/status/owner checks, role escalation denied, allowed+denied mỗi role/collection; emulator test report | Mobile adapter conformance/device tests; không viết/deploy rules thay nhóm trong phase này |
| Backend | Firebase env/app IDs/config/App Check/RC/emulators/demo accounts và cách chạy an toàn | Integrate Android khi có contract, không nhận service-account secret hoặc hard-code key |
| Backend + Web | Atomic review/version/feedback/audit/notification và producer khi không Functions; file contentRef được chấp thuận | Version-bound decision/inbox/reader contracts và F3 latency/test matrix |
| Web | Student submit v1/v2, feedback/status/history; staff announcement form/audience; Web queue requirement của Final | Chỉ Supervisor review/decision/listeners/read receipt; không triển khai Student Mobile/Web thay họ |
| Web + Backend | Joint test seed/reset/runId, deployed build/URL, account/role/assignment và event timing | ARTEMIS Mobile steps + screenshots/observed values; 3 round trips cùng nhóm |
| Nhóm/giảng viên | Xác nhận Lab 3/Final service differences, F3 direction, AI fallback, approved Figma/prototype/success criterion | Ghi quyết định và cập nhật RTM; không tự tuyên bố criterion đã miễn |
| Nhóm | Shared core package/repository/submission structure và code review/report/slides/video ownership | Model/interface thuần Dart và Mobile evidence; chưa move folders/monorepo ở 5.0 |

Không gửi tin nhắn/email tự động cho nhóm trong phase này. Bảng trên là danh sách bàn giao để người phụ trách dùng khi họp thống nhất.

## 7. Quy ước comment tiếng Việt có dấu ở phase triển khai sau

Comment giải thích **vì sao** của invariant hoặc quyết định không hiển nhiên; tên code/API giữ theo convention dự án. Không thêm comment hàng loạt vào source ở 5.0. Vị trí cần ưu tiên:

- Session revoke/callback guard: “Thu hồi phạm vi phiên trước khi hủy listener để kết quả trễ của tài khoản cũ không cập nhật giao diện mới.”
- Transaction/revision/idempotency: “Kiểm tra phiên bản và mã lệnh trong cùng transaction để thao tác thử lại không tạo hai quyết định.”
- Review/version: “Chỉ phản hồi của phiên bản đang đánh giá được công bố; giữ nguyên lịch sử bản nộp trước.”
- Project detach: “Khi nhóm được gỡ, giữ classId trực tiếp của dự án để không mất phạm vi lớp và số liệu Dashboard.”
- AI/PII: “Loại dữ liệu cá nhân trước khi tạo prompt; kết quả AI chỉ là gợi ý và cần giảng viên xác nhận.”
- Offline/ack: “Chỉ báo lưu thành công khi máy chủ xác nhận; dữ liệu chờ đồng bộ chưa phải quyết định đã có hiệu lực.”
- RC fallback: “Dùng giá trị mặc định đã kiểm tra khi cấu hình từ xa không hợp lệ, tránh thay đổi luật duyệt ngoài ý muốn.”

## 8. Gate trước khi gọi Mobile Firebase-ready

1. Các DEP blocking được nhóm xác nhận; role/assignment/file/status/schema/rules không còn suy đoán.
2. Không còn production whole-snapshot commit; DTO validated và repositories scoped; verified session, listeners/cache/async isolation có tests.
3. Mọi Supervisor route dùng real authorized data, đủ loading/empty/error/retry; sample reader/fake profile/notification không còn trong build nộp.
4. F1/F2 và Mobile steps F3 thực hiện đầy đủ alternative/error/recovery; Web↔Mobile realtime và inbox announcements có deployed evidence 3 lượt.
5. AI/RC/export/analytics/crash và các yêu cầu Lab 3 riêng được nghiệm thu đúng scope; không thay yêu cầu bằng bằng chứng loại khác.
6. Giữ 213 regression invariants; adapter/emulator/device/ARTEMIS coverage pass có logs/traces, lỗi/flaky được giải thích; Backend cung cấp rules tests all pass.
7. Cập nhật architecture/design deviations/analytics-plan/test-plan/code-review và submission artifacts chính thức khi tới phase đó; findings có decisions và linked commits khi được phép commit.

## 9. Xác nhận cuối Phase 5.0

- Đã tạo đúng bốn tài liệu yêu cầu; không triển khai các bước tương lai.
- Full regression chạy lại: **213/213 PASS**, 38 giây theo runner, không skip.
- Static analysis chạy lại: **No issues found**, 115,7 giây theo output, exit 0.
- Không chạy ARTEMIS, integration Android, Firebase Emulator, rules hoặc deployed cross-role ở phase này; không gán PASS cho các mục đó.
- Không thêm SDK/config Firebase, Flutter Web/monorepo, không sửa React, không commit/push. Hash trước/sau giống nhau cho **341 file** trong `lib/`, `test/`, `integration_test/`, `assets/`, Android (trừ build/cache), hai pubspec và `D:/UI AI Review/src/`: SHA-256 tổng hợp `754fdbdb02e60c61e12085ee5ff8cf32c1ccac31e71508bc38a35341e53a0bd6`. Đây là phạm vi kiểm tra integrity cụ thể, không phải tuyên bố hash toàn ổ đĩa hoặc toàn workspace tham khảo.
