# Bắt đầu một phiên làm việc với srs-review-ai

Đọc tài liệu này sau `AGENTS.md`. Mục tiêu là xác định đúng phạm vi, nghiệp vụ,
kiến trúc và trạng thái hiện tại trước khi đề xuất hoặc sửa code.

## 1. Lấy trạng thái của checkout

Chạy từ root repo:

```powershell
python tools/project_context.py
```

Script chỉ đọc Git và kiểm tra các đường dẫn bắt đầu đọc. Nó không đọc `.env`,
không gọi cloud, không chạy test và không chứng nhận tính năng hoạt động.
Nếu Git hoặc tài liệu bắt buộc không đọc được, script trả exit code 1.

Ghi HEAD, nhánh, file modified/untracked vào báo cáo đầu phiên. Các file chưa
commit có thể là công việc đang làm của người dùng; đọc diff liên quan trước khi sửa.
Không reset, clean hoặc ghi đè chúng để tạo baseline sạch.

## 2. Đọc phần bắt buộc theo thứ tự

| Thứ tự | Tài liệu | Câu hỏi phải trả lời được |
|---|---|---|
| 1 | [Hiện trạng dự án](project-status.md) | Đã có gì, bằng chứng ở đâu, điều gì còn chưa xác minh? |
| 2 | [Chỉ mục ADR](adr/README.md), rồi [ADR-0013](adr/0013-component-boundaries-flutter-server.md) | Thành phần nào sở hữu từng trách nhiệm? |
| 3 | [ADR-0016](adr/0016-class-roster-and-teacher-decisions.md) và [ADR-0017](adr/0017-class-crud-and-write-key.md) | Backend quản lý lớp, bài nộp, vòng sửa và quyết định như thế nào? |
| 4 | [Ba flow mobile, mục 5](../mobile/docs/mobile-grading-compliance.md#5-rtm-cho-ba-flow-lab-2-hiện-hành) | F1/F2/F3 gồm những bước và ràng buộc gì? |
| 5 | [ADR-0019](adr/0019-firebase-identity-and-data-ownership.md) và [model Firebase](../mobile/docs/firebase-data-model.md) | Nhánh mobile Lab 3 khác Python ở quyền, trạng thái và phiên bản ra sao? |
| 6 | [Cấu hình local](local-environment.md) | Chạy từng app bằng cấu hình nào, secret nằm ở đâu? |

Ở bước 5, phân biệt ADR/source hiện tại với thiết kế đích FastAPI, Firestore và
Cloudinary trong Plan 13. Người dùng đã chốt phạm vi và lựa chọn; chưa có ADR mới
hoặc migration triển khai.
Không tự suy ra phải bỏ FastAPI hoặc mọi client đã dùng chung dữ liệu.

## 3. Đọc sâu theo nhiệm vụ

| Nhiệm vụ | Đọc tiếp |
|---|---|
| Backend/API | [Kiến trúc sau refactor](architecture-refactored.md), [Plan 12 WP2–WP4](plans/12-run-everything-remaining-2026-09-27.md), rồi routes/service/store tương ứng |
| Engine chấm | [Plan 7](plans/7-review-engine-v2-2026-09-15.md), [ADR-0008](adr/0008-kiraai-provider-evaluation.md), [ADR-0010](adr/0010-provider-pacing-and-batching.md), [ADR-0011](adr/0011-persistence-server-cache-and-app-history.md), [review-rules](../review-rules/README.md) và [app-port-map](../review-rules/adapters/app-port-map.md) |
| Mobile học vụ | [Kiến trúc mobile](../mobile/docs/architecture.md), [contracts](../mobile/docs/mobile-firebase-contracts.md), [roadmap migration mục 4](../mobile/docs/mobile-phase5-roadmap.md#4-cách-thay-fakeacademicservice-từng-bước), rồi provider/command/domain liên quan |
| Firestore | [Ghi nhận setup](firebase-connection-setup.md), `mobile/firestore.rules`, `mobile/firebase.json`, service/provider và đường dẫn thực tế trong source |
| Kết hợp Firebase và FastAPI | [Plan 13](plans/13-firebase-fastapi-cloudinary-integration.md), [progress](plans/13-progress.md), [prompt agent](plans/13-handoff-prompt.md); [roadmap nền](firebase-backend-integration-roadmap.md) giữ bối cảnh đề xuất. Plan đã lưu lựa chọn người dùng, các WP chưa triển khai |
| Admin | `admin_web/lib/main.dart`, auth service, repositories và quyền đọc tương ứng; không coi mock auth là Admin đã xác thực |
| Lab 3/demo | [Checklist tổng hợp](lab3-completion-checklist-2026-11-05.md), [review theo hai PDF](lab3-review-2026-11-05.md), bằng chứng mới hơn được dẫn trong [hiện trạng](project-status.md) |

Với Lab 3, đọc lại hai PDF được nêu trong checklist nếu cần xác định yêu cầu chấm.
Nếu máy mới không có PDF, dùng bản text theo trang được dẫn trong báo cáo review,
và ghi rõ nguồn đã đọc. Không thay bằng đề Patrol/Final cũ.

## 4. Đối chiếu một flow với source

1. Chọn thao tác cụ thể của nhiệm vụ, chẳng hạn nộp lại tài liệu hoặc tạo project.
2. Lần từ route/màn hình qua ViewModel, repository/service đến nơi lưu và response.
3. Xác định ai được thực hiện, điều kiện chuyển trạng thái và dữ liệu phải giữ nguyên.
4. Đọc test và evidence liên quan; kiểm ngày, HEAD, môi trường và phạm vi của chúng.
5. Ghi riêng code hiện có, kết quả chạy trước đây và phép kiểm vừa thực hiện.

Đối với Firestore, kiểm cả path writer, path reader và Rules. Có Firebase config
không chứng minh dữ liệu cloud đã tồn tại. Có `snapshots()` không chứng minh hai
client đã đồng bộ thành công. JSON/RAM, cache SQLite và file Cloudinary có vai trò khác nhau.

## 5. Báo cáo lại trước khi đổi kiến trúc

Báo cáo ngắn gồm:

- HEAD/nhánh và thay đổi có sẵn liên quan đến nhiệm vụ.
- Mục tiêu người dùng, flow và thành phần chịu trách nhiệm.
- Hiện trạng có dẫn source/evidence, cùng phần chưa xác minh.
- Mâu thuẫn giữa docs/code hoặc giữa hai mô hình cần giải quyết.
- Bước triển khai kế tiếp và cách chứng minh kết quả.

Nếu nhiệm vụ chỉ yêu cầu khảo sát, dừng ở báo cáo. Nếu đã được yêu cầu triển khai,
tiếp tục trong phạm vi đó; không tự biến boot sequence thành yêu cầu xin phép mới.
Không mặc định chạy toàn bộ tests, deploy rules, gọi LLM hoặc thực thi Plan 12 chỉ
để nạp context. Chọn phép kiểm phù hợp với việc đang làm.

## 6. Cập nhật bàn giao trước khi kết thúc

Cập nhật [project-status.md](project-status.md) khi có thay đổi về khả năng, nơi lưu
dữ liệu, trạng thái nghiệm thu hoặc bước tiếp theo. Ghi:

- Ngày, HEAD, phạm vi working tree và các file quan trọng.
- Việc đã làm, lệnh kiểm và đường dẫn log; nếu chưa chạy thì ghi chưa chạy.
- Việc còn thiếu, phụ thuộc người dùng/cloud/device và bước tiếp theo cụ thể.
- Quyết định kiến trúc mới đã được ghi ở đâu; đề xuất chưa chốt phải có nhãn riêng.

Giữ chi tiết lịch sử trong ADR/evidence. Hiện trạng chỉ dẫn đến chúng, không chép
số test cũ thành kết quả mới. Dùng [prompt tiếp quản ở root](../promt.txt) cho phiên sau.

## 7. Những tài liệu dễ bị đọc sai

| Tài liệu | Cách sử dụng |
|---|---|
| `architecture.md`, `arch-server-notes.md`, `tech-lead-brief.md` | Bối cảnh ban đầu; một số mô tả proxy stateless, cache RAM và cây file đã cũ |
| `plans/11-*`, `plans/12-*` | Đọc cả kết quả cập nhật và ADR sau đó; phần “chưa có” ở đầu plan có thể đã được triển khai |
| `plans/12-handoff-prompt.md` | Chỉ giao WP thuộc Plan 12; không phải prompt tiếp quản mặc định của toàn dự án |
| Mobile docs tháng 10 | Thiết kế/nghiệp vụ và lịch sử refactor; câu “chưa Firebase” có thể đã được source tháng 11 thay đổi |
| `lab3-review-2026-11-05.md` | Baseline review tại HEAD ghi trong báo cáo; lỗi bootstrap đã có bản sửa sau đó |

Thứ tự đánh giá: yêu cầu hiện tại của người dùng xác định phạm vi; ADR xác định
quyết định và phạm vi áp dụng; source hiện tại xác định triển khai; evidence xác
định điều đã chạy trong môi trường được ghi. Nếu chúng mâu thuẫn, chỉ rõ mâu thuẫn.
