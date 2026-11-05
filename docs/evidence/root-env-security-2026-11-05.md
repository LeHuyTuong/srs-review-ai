# Tách API key khỏi source, dùng .env root

## Thay đổi

- Bốn giá trị Firebase client hiện có đã được thêm vào `.env` root. Giữ nguyên toàn bộ nội dung cũ của file; không ghi giá trị key vào báo cáo/log.
- Mobile Android/Web và Admin Web đọc key bằng `String.fromEnvironment`. Runner `tools/flutter_env.py` chỉ truyền allowlist của app đang chạy, không truyền toàn bộ `.env`.
- Hai file Android `google-services.json` được sinh lại từ template `.example`. File thật và artifact `.env` Flutter cũ đã bỏ Git tracking, giữ local và ignore.
- Server ưu tiên biến môi trường triển khai, sau đó `.env` root, rồi fallback `server/.env`.
- Guardrail dùng danh sách tracked và untracked không bị ignore; file đã track vẫn được kiểm kể cả khi có ignore. Git không đọc được, input rỗng hoặc danh sách bị cắt đều không được báo pass.
- Sửa false positive khi regex có anchor bị nhận nhầm là phép gán secret. Test vẫn bắt phép gán token/API key thật bằng giá trị giả lập.
- CI chạy bộ unittest cho runner và guardrail trước lượt kiểm tra chính.

Không tìm thấy khối `FirebaseOptions macos` được nêu trong yêu cầu trong working tree này. Không thêm key macOS chưa được code dùng. Không thay project Firebase hoặc sửa luồng Google Sign-In trong đợt này.

## Kiểm chứng

| Phép kiểm | Kết quả |
| --- | --- |
| Scan literal Google API key trong Git candidates hiện tại | 0 file |
| `.env` root và hai JSON native thật | Được Git ignore, không còn được track |
| Defines sinh cho mobile/admin/desktop | Chỉ chứa đúng allowlist, giá trị khớp `.env` root |
| `python -m unittest discover -s tools/tests -v` | 11 pass |
| Test server về ưu tiên `.env` | 2 pass |
| Mobile bootstrap test, có defines và không có defines | Mỗi lượt 12 pass |
| Mobile và Admin Web analyze | Không có issue |
| Chrome integration qua runner | Pass, Firebase thật khởi tạo và hiện LoginScreen |
| Android debug APK qua runner | Build thành công |
| Admin Web debug build qua runner | Build thành công |
| Quét 16 file JS/WASM của Admin Web | 0 match với giá trị key server trong `.env` |
| Quét nội dung APK | Không có `.env` asset; 0 match với giá trị key server |
| Ruff check và format cho server, runner, tools tests | Pass |
| `git diff --check` | Pass |

Giá trị key client và key server trong `.env` hiện tại không trùng nhau. Phép quét bundle đọc nội dung file đã build và từng entry trong APK, không chỉ kiểm tên biến. Nó chỉ chứng minh các giá trị được kiểm không xuất hiện trong hai artifact này, không phải một đánh giá bảo mật toàn hệ thống.

Guardrail `secrets` đã pass. Guardrail toàn repo vẫn exit 1 với 61 vi phạm có sẵn ở MVVM layering, design tokens và full-screen surfaces. Không sửa các phần UI này trong đợt tách key.

Suite server thu thập 360 test: 358 pass, 1 skip, 1 fail tại `test_store.py::test_reading_refreshes_recency_so_a_hit_is_not_the_next_victim`. Chạy riêng test này vẫn fail. Test tạo SQLite cache trong thư mục tạm; code cache và test đó không được sửa ở đây.

## Chạy lại

Các lệnh dưới đây chạy từ root repo:

```sh
python tools/flutter_env.py mobile run -d chrome
python tools/flutter_env.py admin_web run -d chrome
python tools/flutter_env.py mobile build apk --debug --no-pub
python tools/flutter_env.py admin_web build web --debug --no-pub
```

Hướng dẫn máy mới/IDE và biến cấu hình: [local-environment.md](../local-environment.md).

Thay đổi chưa được commit. Bỏ tracking là thao tác trên index, không xóa file local. Literal cũ vẫn có trong lịch sử Git; chưa rewrite lịch sử, thu hồi hoặc đổi key ở nhà cung cấp. Firebase client key vẫn có thể xuất hiện trong app đã build theo thiết kế của SDK.
