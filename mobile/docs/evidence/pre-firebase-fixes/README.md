# Phase 4.5 — sửa lỗi audit và ổn định trước Firebase

Ngày: **26/10/2026**, Asia/Saigon. Flutter `D:/SRS-Review-AI-Mobile`; React `D:/UI AI Review` chỉ đọc. Mobile chỉ dành cho Supervisor/Giảng viên; Student tiếp tục dùng React Web. Giữ bản sửa Supervisor-only Login trước đó.

**Kết quả:** năm lỗi runtime/data Nhóm A đã được sửa, regression tests PASS và các đường liên quan đã được kiểm chứng trên Android 390dp. Bốn business projections được chỉ ra trong AUD-A01 đã chuyển khỏi View. AUD-A03 được cải thiện có giới hạn bằng typed Course DTO/command, error codes và session boundary; migration toàn bộ repository/backend vẫn **PARTIAL**, có kế hoạch cụ thể. Không tuyên bố ứng dụng đã hoàn thành Lab 3 hoặc Firebase-ready toàn bộ.

| Kiểm chứng | Kết quả mới |
|---|---|
| `flutter analyze --no-pub` | **No issues found** |
| Targeted Nhóm A trước Nhóm B | **34/34 PASS**, gồm 15 regression mới + 19 test Phase 4 hiện có |
| Targeted sau refactor/cập nhật ID contract | **81/81 PASS** |
| Bổ sung test vòng đời repository/provider thực | **1/1 PASS** |
| Full `flutter test --no-pub` | **213/213 PASS**, đúng **một lượt cuối**, 39 giây |
| Native Android | Search Gboard, duplicate Course, giữ semester sau mutation, Group detach→Project→Dashboard, A→logout→B và Back đã quan sát |
| Integrity | Không đổi fixture; React sạch; không xóa/skip test; không commit/push hoặc Firebase integration |

Baseline thực tế gần nhất là **189 test** sau bản sửa Supervisor-only Login; 185 là baseline Final Audit trước đó. Phase này thêm **24 test** (16 runtime/session/widget + 8 boundary/projection). Hai test cũ được điều chỉnh cách tra Course theo code/ID ổn định thay vì giả định internal ID bằng slug; vẫn giữ đầy đủ kiểm tra tạo/hủy/trùng mã, không hạ expectation nghiệp vụ.

## Báo cáo và evidence

- [Giải quyết từng issue](issues-resolution.md): root cause, before/after, file, test, native, hạn chế.
- [Thay đổi kiến trúc và migration](architecture-changes.md): session vs shared fake data; typed boundary; phần chưa làm.
- [Kết quả regression/native](regression-results.md): cả lần điều tra thất bại và xác nhận cuối.
- [Danh sách file thay đổi](source-changes.json), [dependency check](dependency-check.json), [analyze](analyze.log), [full tests](full-tests.log).

## Những thay đổi chính

1. **AUD-U01:** search có controller/identity ổn định; clear/restore đồng bộ có chủ ý, không gọi requestFocus sau rebuild. Class search cùng dùng component này. Student directory đã có controller ổn định, được bổ sung regression kiểm tra nhưng không thêm Student Mobile workflow. Course list hiện không có search, nên không tự thêm.
2. **AUD-A02:** định danh mock có userId và generation; scope được revoke ngay khi logout. Repository, bộ lọc, saved views, draft/reading/AI/enrollment UI state được invalidate theo scope; navigator tạo lại theo session. Callback async cũ không cập nhật UI hoặc commit sau khi scope bị revoke.
3. **AUD-B03:** Course mới có internal ID độc lập code; intent create/update rõ ràng. Kiểm tra duplicate ở command và commit, revision conflict nguyên tử; legacy IDs/references không bị migrate ngầm.
4. **AUD-B02:** dùng chung resolver Group.classId→Project.classId dự phòng; Project còn Class hợp lệ vẫn có trong Dashboard và list sau detach.
5. **AUD-B01:** lựa chọn học kỳ độc lập lần tải Dashboard, giữ qua mutation/retry, fallback khi archive/delete, reset khi đổi phiên.
6. **AUD-A01/A03:** chuyển projections cụ thể sang domain/VM; thêm typed Course slice và phân loại domain errors; giữ tương thích các workflow còn dùng snapshot.

## Giới hạn còn lại

FakeAcademicService là **shared fake server trong bộ nhớ tiến trình**, không phải cache riêng của user. Các Course/Project/Group đã commit hợp lệ vẫn còn sau logout trong cùng lần chạy. Filter, draft, saved view và kết quả async của phiên mới phải độc lập. Vì vậy không dùng lại assertion audit cũ “Course đã commit phải biến mất khi đổi email” để xác nhận isolation: yêu cầu Phase 4.5 đã phân biệt rõ shared committed data với user-specific cache. Fixture gốc luôn bất biến; khởi động app mới đọc lại fixture.

Chưa có Google/Firebase UID thật, server authorization/ownership rules, Firestore transaction/query/subscription, real-data/FCM/Storage/export/Analytics/Crashlytics/Remote Config hoặc ARTEMIS. Profile và actor demo vẫn lấy thông tin giảng viên mẫu chung; email mock B xác định client scope, không chứng minh tài khoản/permissions thật. Các issue final-submission khác giữ nguyên.

Đã kiểm tra native ở 390dp với 12 checkpoint chọn lọc, không screenshot sweep. Không đổi bố cục/design system ngoài sửa lifecycle search. Dữ liệu kiểm thử chỉ nằm trong app fake; sau logout/Android Back và mở lại app ở Login, engine mới đọc fixture gốc. Size/density đã khôi phục physical 1080×2340 / 440. Phase dừng sau báo cáo.
