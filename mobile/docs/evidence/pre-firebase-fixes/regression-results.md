# Kết quả regression và Android native

26/10/2026. Không dựa vào báo cáo PASS cũ để đóng issue. Không sửa fixtures, xóa/skip test hoặc chạy lại screenshot sweep.

## Automated execution

| Lượt | Phạm vi / log | Kết quả thực tế |
|---|---|---|
| Nhóm A lần đầu | `group-a-initial-failures.log` | 28 PASS / 6 FAIL: implementation thử có provider circular dependency khi logout, một UI test dùng font mặc định gây overflow. Đã sửa ownership token và load Inter/390dp như app thật |
| Nhóm A trước Nhóm B | `group-a-tests.log` | **34/34 PASS**; gồm regression runtime và test Phase4 hiện có |
| Targeted sau Nhóm B | `targeted-tests.log`, bản giữ `targeted-initial-failures.log` | 198 PASS / 2 FAIL: hai test cũ giả định Course ID=slug; không phải mất Course. Các workflow còn lại PASS |
| Targeted sau cập nhật ID lookup | `targeted-corrected-tests.log` | **81/81 PASS** gồm hai regression files và academic VM/widget tests bị ảnh hưởng |
| Repository/provider thực | `session-provider-test.log` | **1/1 PASS**, bổ sung sau lượt trên |
| Analyze cuối | `analyze.log` | **No issues found**. Trước đó có một lint thiếu braces đã sửa trước xác nhận cuối |
| Full suite cuối | `full-tests.log` | **213/213 PASS**, 39 giây, chỉ chạy một lượt full |

Baseline gần nhất 189, thêm 24 test: 16 trong `test/pre_firebase_regression_test.dart`, 8 trong `test/pre_firebase_boundaries_test.dart`. Hai test cũ trong `academic_view_model_test.dart` và `academic_widget_test.dart` đổi từ lookup slug sang tìm Course theo code rồi kiểm tra ID/name đã lưu; bổ sung assertion ID khác slug. Cancel vẫn kiểm tra không có Course mới, duplicate vẫn phải throw. Không nới điều kiện để che lỗi overwrite.

## Regression coverage

| Issue | Assertions quan trọng |
|---|---|
| U01 | Năm route; nhập từng ký tự qua test keyboard; focus node giữ identity/hasFocus; keyboard visible; mid-string caret; filter đúng; external clear; Back không controller exception |
| A02 | Logout revoke scope đồng bộ, same-user generation mới, A→B, repository instance mới/cũ denied, shared committed data còn, list/class/saved filters reset, Dashboard reset theo scope, late AI không tăng revision, late fake commit không publish, navigator disposed và Back không mở Supervisor |
| B03 | Slug-collision codes tạo hai identity, đổi code giữ ID, duplicate create/edit/unknown ID atomic, original edges/history không đổi, fake commit ID/code duplicate/stale revision, typed create-ID collision, concurrent commands chỉ một success |
| B02 | Valid linked Project trước và sau xóa group rỗng, Class/Project list cùng có Project, Dashboard active total bằng query chuẩn, group không tái xuất hiện, review history không đổi |
| B01 | Group/Project/Class mutation và retry giữ selection; archive/delete fallback hợp lệ; All giữ nguyên; logout/login reset |
| A01 | Pure projections: phase/date sort/tie-break; group membership count/dedupe; document status tabs/count/priority/order; disabled/nonnumeric criterion; không mutate input |
| A03 | DTO malformed types/required fields, deep copy/unknown retention, typed command used by VM/default fake, optimistic revision/concurrency và errors |

## Native method và giới hạn

Chạy **app thật từ lib/main.dart**, không chạy integration-test entrypoint. Pixel_4a_API_34/emulator-5554; 1170×2532 px, density480 = **390dp**. `native-launch.log`, `android-390-config.log`. Dùng computer-use điều khiển cửa sổ; khi cần ASCII form input/Android Back hoặc vuốt Dashboard, dùng Android input bridge, không gọi ViewModel/repository trực tiếp.

Riêng search regression được nhập bằng **bấm từng phím trên Gboard thật**, không phải bơm toàn chuỗi. `native-ime.log` xác nhận `mInputShown=true`, `mIsInputViewShown=true`. `ui-actions.json` ghi các thao tác đã dispatch, không được hiểu mọi nhãn action là assertion; kết quả dưới đây dựa vào quan sát/ảnh checkpoint.

| Flow ảnh hưởng | Kết quả native mới | Evidence |
|---|---|---|
| Search liên tục | Focus Projects search→Gboard s,m,a,r,t; đủ `smart`, 2 kết quả, không refocus hoặc đóng IME. Clear query/filter giữ IME và trở về 14 Project toàn học kỳ (trước tạo mới) | `390-search-smart-gboard.png`, `390-search-cleared-ime.png` |
| Course validation | SWP391 + Duplicate course→save bị chặn “Mã môn đã tồn tại”; giữ form. Thêm P45 vào code→SWP391P45 save thành công; Profile môn học 4→5 | `390-course-duplicate-blocked.png`; action log |
| Dashboard filter | Chọn Spring2027 trước Course mutation; quay về sau save vẫn Spring2027. Tạo Project/xóa Group tiếp theo cũng không tự reset; sau đó chủ động chọn Fall2026 để đọc count | `390-semester-before.png`, `390-semester-after-mutation.png` |
| Group detach | SE1701 Group09 rỗng→tạo P45 Detached→menu Xóa nhóm/Confirm→Class về 8 nhóm. Project còn đúng SWP391/SE1701/group “—”. Dashboard Fall2026/Truy cập nhanh “Đang thực hiện 13”, khớp Project list | `390-group-project-before-detach.png`, `390-detached-project-list.png`, `390-dashboard-detached-count-13.png` |
| A→logout→B | A có Projects query P45 và All-semester. Logout→nhập b@example.test→login→Dashboard root. Projects query trống, default Fall2026/active; shared active projects vẫn 13, không xóa domain data đã commit | `390-login-identity-b.png`, `390-session-b-cleared-search-shared-data.png` |
| Back sau đổi phiên | Logout B→Android Back ra launcher, không vào protected route. Mở lại app vẫn Login | `390-logout-back-launcher.png`, `390-reopen-signed-out.png` |

Không quan sát crash, overflow hoặc stuck modal trong các đường này. `android-runtime.log` PID 28087 không có các chuỗi FATAL EXCEPTION/Unhandled Exception/RenderFlex/overflowed khi kiểm tra; không xem đó là chứng minh mọi runtime path. Profile/actor vẫn thông tin demo giảng viên chung, không là verified Firebase user.

Không cần thêm native 360/412 vì không đổi layout; widget tests cũ tại cả ba width vẫn nằm trong full suite PASS. Có **12 PNG checkpoint**, không quét mọi màn. Chưa chạy ARTEMIS, không gọi manual native hoặc Flutter widget tests là Google ARTEMIS. Archive/delete semester, slug collision và async race được kiểm chứng tự động; không gán thành ca native đã thao tác.

## Integrity / environment

- `source-before.json` chụp 166 file gốc trong lib/test/integration_test/assets trước Phase4.5. `source-changes.json`: 27 file thay đổi, 7 file thêm; **không xóa file, không thay fixture**. Các thay đổi gồm các provider/VM cần thiết để scope user state, không thêm Student workflows.
- `dependency-check.json`: 101 lib Dart files, ba SCC legacy không đổi, **không SCC mới**, không ViewModel import screens/widgets. Đây là kiểm tra import, không tuyên bố refactor mọi responsibility đã hoàn hảo.
- `react-status.log` trống = React git status sạch. Không commit/push.
- `emulator-before.log` và `emulator-after.log` cùng physical1080×2340/density440. Không đổi IME setting; chỉ đọc trạng thái.
- Domain test data chỉ trong fake process; sau logout/Back Activity kết thúc và mở engine mới về Login/fixture gốc. Không ghi fixture hoặc dữ liệu lâu dài ngoài emulator. Build tools làm mới build/cache bình thường.
- Không sửa source sau analyze sạch/full PASS. Kết thúc phase ở bước báo cáo.
