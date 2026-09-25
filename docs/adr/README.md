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
| [0007](0007-m3-adaptive-thresholds.md) | M3 window class cho rail; dialog căn giữa miễn trừ trên phone | Accepted |
| [0008](0008-kiraai-provider-evaluation.md) | Không dùng KiraAI làm provider chính; giữ làm fallback vision có điều kiện | Accepted |
| [0009](0009-rubric-v3-weights-and-uc-ceiling.md) | Rubric v3: weights `.25/.40/.20/.15`, bỏ trần 25 use case | Accepted — **chưa chạy test** |
| [0010](0010-provider-pacing-and-batching.md) | Proxy giữ nhịp provider (pacer toàn cục), app gộp 6 unit/call, 502 là "đã retry xong" | Accepted |
| [0011](0011-persistence-server-cache-and-app-history.md) | Bỏ "không có DB": cache server bằng SQLite (stdlib), lịch sử app bằng sembast sau interface `SessionStore` | Accepted |
| [0012](0012-issue-criterion-identity.md) | Finding mang hai thứ: `criterion_id` (tiêu chí, sửa được) và `type` (lớp lỗi, enum đóng + `other`); nhãn sai thì uốn, không làm hỏng unit | Accepted |

**Số tiếp theo: 0013.**

Luật chấm SRS/SDS **không** ghi ở đây — chúng nằm ở `review-rules/RULEBOOK.md` với hệ version riêng (§10). ADR chỉ dành cho quyết định về *code* của repo này.
