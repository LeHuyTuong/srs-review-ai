# Sửa lỗi khởi động Firebase trên Chrome và Android

## Nguyên nhân và thay đổi

Commit merge `8deba39` giữ thân `_registerCrashHandlers()` nhưng làm mất khai báo hàm, điều kiện bỏ qua web và các import liên quan. Các lệnh còn nằm ngoài mọi hàm trong `main.dart`, gây lỗi cú pháp dây chuyền. Đã xóa đoạn sót này và giữ bootstrap làm điểm đăng ký error handler duy nhất.

Bootstrap, provider Crashlytics và mục thử crash dùng chung kiểm tra nền tảng. Web luôn bỏ qua Crashlytics, kể cả khi trình duyệt báo Android hoặc macOS. FCM background handler chỉ đăng ký trên native. Hai error handler hiện có và quy tắc collection trong debug được giữ trên nền tảng hỗ trợ. Các callback SDK có thể được inject trong test.

Firebase CLI đã tạo Web App `srs-review-ai-mobile-web` trong project `srs-ai-prm`, app ID `1:1025053844292:web:d0989789698826cf872d11`. Cấu hình Web được lấy bằng `apps:sdkconfig`, bổ sung vào options và metadata FlutterFire. Options Android, OAuth client ID và `android/app/google-services.json` không đổi. Không dùng cấu hình Firebase của admin web.

Trong lúc kiểm tra đã phát hiện và sửa thêm hai lỗi cản build:

- Khôi phục `firebase_storage: ^14.0.1`, dependency đã được `srs_service.dart` dùng nhưng mất sau merge. Lockfile resolve ra 14.0.1; không nâng các package khác.
- Bỏ khai báo plugin Crashlytics trùng ở cả app Gradle và settings Gradle; giữ phiên bản 3.0.6 trong khối FlutterFire.

## Kết quả kiểm chứng

Môi trường: Windows, Flutter 3.47.4, Dart 3.13.3, Chrome 156.0.8078.80.

| Kiểm tra | Kết quả |
| --- | --- |
| `flutter analyze --no-pub` | Pass, không có issue |
| `flutter test --no-pub --reporter expanded` | 246 pass, 3 fail do thiếu baseline ảnh |
| 12 test mới trong `test/firebase_bootstrap_test.dart` | Pass trong suite host |
| Chrome integration với Firebase thật | Pass, app hiện `LoginScreen`, project là `srs-ai-prm`, provider dùng no-op khi Firebase đã khởi tạo |
| `flutter build apk --debug --no-pub` | Pass, tạo `build/app/outputs/flutter-apk/app-debug.apk` |
| Dart format check cho các file Dart đã sửa/thêm | Pass |
| `git diff --check` | Pass |

Test bootstrap kiểm tra thứ tự khởi tạo trước SDK, collection debug mặc định/tường minh, hai error handler nhận đúng lỗi và stack, lỗi Firebase được truyền ra, no-op service không cần plugin, options đúng project và mục thử crash chỉ hiện trên nền tảng hỗ trợ. Test widget và integration rút hết hàng đợi exception.

Ba test ảnh fail nằm trong `behavior_preservation_visual_test.dart`, thiếu `.local/behavior-refactor/visual/360-login.png`, `390-login.png`, `412-login.png`. Không tạo lại baseline trong đợt sửa này.

APK debug có SHA-256 `e99e0f0f8921a0c182c00c2bd9dba2cacdcb3ef5ae5d9e7405166be5ed13c882`. Không có thiết bị hoặc emulator qua `adb devices`, nên chưa xác minh chạy trực tiếp trên Android. Không kích hoạt crash thật. Chưa kiểm chứng đăng nhập Google; tiêu chí Chrome của đợt này là khởi động tới màn hình đăng nhập.

## Lệnh chạy lại

Sau đợt tách key khỏi source, dùng runner đọc `.env` root. Từ root repo:

```sh
python tools/flutter_env.py mobile pub get
python tools/flutter_env.py mobile analyze --no-pub
python tools/flutter_env.py mobile test --no-pub test/firebase_bootstrap_test.dart
python tools/flutter_env.py mobile run -d chrome
python tools/flutter_env.py mobile build apk --debug --no-pub
```

Để chạy bài integration Chrome, cần ChromeDriver khớp phiên bản Chrome đang chạy. Khởi động driver ở localhost port 9516 trước, rồi chạy:

```sh
python tools/flutter_env.py mobile drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/firebase_startup_test.dart -d web-server --driver-port=9516 --headless --web-port=54614
```

## Các kiểm tra chưa xanh

`python tools/check_guardrails.py` báo 68 vi phạm ở tầng secrets, MVVM layering, design tokens và full-screen surfaces. Trong đó có **một flag mới** cho API key cấu hình Firebase Web; phép so với options trước thay đổi cho 6 flag secrets, sau thay đổi là 7. Đây là giá trị cấu hình client lấy từ Firebase CLI. Không sửa hoặc thêm ngoại lệ vào guardrail trong đợt này. Native plugin và line-ending checks pass; line-ending check đọc index hiện tại, chưa phải index sau stage các thay đổi này.

Đã tìm Ruff trong cả `server/.venv/Scripts`, `server/.venv/bin` và thử `server/.venv/Scripts/python.exe -m ruff`; môi trường hiện tại không có executable hoặc module Ruff. Không có thay đổi server.

Một lượt bổ sung `flutter test --platform chrome test/firebase_bootstrap_test.dart` bị kẹt ở bước load, chưa chạy các test. Đọc console của trình duyệt test thấy CanvasKit JS và WASM tại `/canvaskit/chromium/` trả HTTP 404; request trực tiếp xác nhận 404. Đã dừng lượt bổ sung này. Kết quả Chrome integration ở trên chạy bằng `flutter drive` và đã pass độc lập.
