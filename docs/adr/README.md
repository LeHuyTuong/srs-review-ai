# ADR index

Mỗi quyết định kỹ thuật có một file, đánh số tăng dần, không sửa số cũ. Bỏ một quyết định → mở ADR mới có `Status: Supersedes ADR-NNNN`, giữ file cũ nguyên trạng.

| # | Quyết định | Status |
|---|---|---|
| [0001](0001-architecture.md) | Architecture and scope — app Flutter + proxy FastAPI, key chỉ nằm ở server | Accepted |
| [0002](0002-no-codegen.md) | Model viết tay thay cho freezed / json_serializable | Accepted |
| [0003](0003-syncfusion-licence.md) | Syncfusion để trích text PDF, và licence thật sự đòi gì | Accepted |
| [0004](0004-model-selection.md) | Chọn model, và ba chi tiết REST đủ sức làm hỏng demo | Accepted |
| [0005](0005-run-cap-vs-quota.md) | Run cap 60 nằm trên quota 50/ngày/người — ai gánh phần chênh | Accepted |
| [0006](0006-desktop-edition-three-decisions.md) | Desktop edition: window sizing native-only, command registry, uplift màn lớn | Accepted |
| [0007](0007-m3-adaptive-thresholds.md) | M3 window class cho rail; dialog căn giữa miễn trừ trên phone (D2 bị [0014](0014-full-screen-modal-surfaces.md) thu hồi 2026-10-07, luật đã xoá) | Accepted |
| [0008](0008-kiraai-provider-evaluation.md) | Không dùng KiraAI làm provider chính; giữ làm fallback vision có điều kiện | Accepted |
| [0009](0009-rubric-v3-weights-and-uc-ceiling.md) | Rubric v3: weights `.25/.40/.20/.15`, bỏ trần 25 use case | Accepted — **chưa chạy test** |
| [0010](0010-provider-pacing-and-batching.md) | Proxy giữ nhịp provider (pacer toàn cục), app gộp 6 unit/call, 502 là "đã retry xong" | Accepted |
| [0011](0011-persistence-server-cache-and-app-history.md) | Bỏ "không có DB": cache server bằng SQLite (stdlib), lịch sử app bằng sembast sau interface `SessionStore` | Accepted |
| [0012](0012-issue-criterion-identity.md) | Finding mang hai thứ: `criterion_id` (tiêu chí, sửa được) và `type` (lớp lỗi, enum đóng + `other`); nhãn sai thì uốn, không làm hỏng unit | Accepted |

| [0013](0013-component-boundaries-flutter-server.md) | Ranh giới component thật: `app/lib/` thành 6 component headless + `WorkspaceViewModel` thành façade trên 7 controller; `server/app/` thành api/application/domain/infrastructure/config/contracts | Accepted |
| [0014](0014-full-screen-modal-surfaces.md) | Mọi modal là bề mặt full-screen qua `showFullScreenSurface`/`WFullScreenSurface`; cấm họ bottom sheet trong `app/lib` (luật 8 guardrail) | Accepted |
| [0015](0015-role-vs-form-factor-and-phone-sheets.md) | `AppRole` (build + phiên) tách khỏi `AppPlatform` (thiết bị); lệnh cấm bottom sheet giữ nguyên phạm vi, không nới cho phone | Accepted |
| [0016](0016-class-roster-and-teacher-decisions.md) | Lớp học là `class_id` capability (**không thu hồi được**); quyết định của giáo viên **append** không ghi đè; đúng khi **self-hosted**; "đã đọc" là việc của máy | Accepted — **bị [0020](0020-real-accounts-replace-the-capability-posture.md) đảo 2026-10-08** (mô hình capability → tài khoản thật) |
| [0017](0017-class-crud-and-write-key.md) | Lớp học là **full CRUD**; ghi khác app token (mỗi lớp có `write_key` riêng, so bằng `compare_digest`); `class_id` nằm trên **submission** chứ không có list trong file lớp; `DELETE` lớp **không xoá bài nhóm** | Accepted |
| [0018](0018-contradiction-pass-scope-row-shaped-documents.md) | `crossArtifactName` (chain 1) chỉ bắn trên tài liệu hình dòng (SDS/dictionary); SRS văn xuôi trả 0 là kết quả được thiết kế — số đo cơ chế kèm theo; không thêm "N/A" và không nới extractor khi chưa có gold set | Accepted |
| [0019](0019-web-ui-is-a-mock-contract-sync.md) | web-ui là mock (không gọi server); `ReviewEventKind` thu về `approved \| changes_requested \| resubmitted` (bỏ `needsRevision`/`rejected` — chúng là `DocumentStatus`); decision vocabulary vào `contracts/review.schema.json`, bump 1.1.0→1.2.0; wire thật là bước sau với cổng credential của browser | Accepted — **bị [0020](0020-real-accounts-replace-the-capability-posture.md) đảo 2026-10-08** (web-ui thôi là mock, gọi `/auth/*`) |
| [0020](0020-real-accounts-replace-the-capability-posture.md) | **Đảo ADR-0016**: bỏ mô hình `class_id` capability, thay bằng bảng `users` + mật khẩu băm `scrypt` + session cookie `HttpOnly`; mọi route biết người gọi; `GET /submissions` lọc theo danh tính; web-ui và app Flutter đều có màn đăng nhập. Đè brief "KHÔNG làm tài khoản/đăng nhập thật" theo quyết định chủ sở hữu | Accepted |

**Số tiếp theo: 0021.**

Luật chấm SRS/SDS **không** ghi ở đây — chúng nằm ở `review-rules/RULEBOOK.md` với hệ version riêng (§10). ADR chỉ dành cho quyết định về *code* của repo này.
