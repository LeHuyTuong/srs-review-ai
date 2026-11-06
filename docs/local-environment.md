# Cấu hình local bằng .env ở thư mục root

File local là `F:\study\PRM\srs-review-ai\.env`. File này đã được Git ignore. Máy mới copy `.env.example` ở root thành `.env` và điền giá trị từ Firebase SDK configuration hoặc nơi quản lý secret của nhóm. Không đưa file đã điền lên Git.

## Chạy Flutter

Từ root repo:

```sh
python tools/flutter_env.py mobile run -d chrome
python tools/flutter_env.py admin_web run -d chrome
python tools/flutter_env.py mobile build apk --debug
python tools/flutter_env.py mobile test test/firebase_bootstrap_test.dart
```

Runner đọc `.env`, chỉ chọn các biến thuộc app đang chạy, sinh `.dart_tool/firebase-defines.json` và truyền đường dẫn này bằng `--dart-define-from-file`. Code Dart đọc bằng `String.fromEnvironment`; không đóng gói `.env` làm Flutter asset. Biến môi trường của hệ điều hành/CI ưu tiên hơn giá trị trong `.env`.

`GEMINI_API_KEY`, `APP_TOKEN`, key Groq/OpenRouter và mọi biến ngoài allowlist không được đưa vào defines của Flutter. Không truyền trực tiếp toàn bộ `.env` root cho `--dart-define-from-file`.

## Chuẩn bị một lần để chạy `flutter run` trần

`String.fromEnvironment` là hằng **compile-time**: `flutter run` không có đường nào
tự đọc `.env`, nên chạy `flutter run` trần trong `mobile/` sẽ không có client key
và app dừng ở `Missing Firebase client configuration`. Chuẩn bị cấu hình **một
lần** bằng runner:

```sh
python tools/flutter_env.py mobile prepare
```

Lệnh này sinh ba file cục bộ, đều bị Git ignore:

| File | Dùng cho |
|---|---|
| `mobile/.dart_tool/firebase-defines.json` | đường `--dart-define-from-file` của runner |
| `mobile/android/app/google-services.json` | Gradle plugin `com.google.gms.google-services` |
| `mobile/web/firebase-config.js` | web đọc client key lúc chạy |

Sau đó, trong `mobile/`, `flutter run` chạy được mà không cần cờ nào:

- **Web**: `web/index.html` nạp `firebase-config.js`, app đọc
  `window.firebaseApiKey` lúc chạy
  (`mobile/lib/core/services/web_firebase_config_web.dart`).
- **Native**: `firebase_bootstrap.dart` gọi `Firebase.initializeApp()` không kèm
  options, nên Firebase lấy cấu hình từ `google-services.json` do Gradle plugin sinh.

Khi có `--dart-define`, giá trị define được ưu tiên, nên đường runner và CI
giữ nguyên hành vi cũ. Nếu thiếu cấu hình, app nêu đúng lệnh cần chạy. Admin dùng
quy trình tương tự với đối số `admin_web`. Không commit các file đã sinh.

## Port cố định cho web

Mỗi app có một `web_dev_config.yaml` ở thư mục app, nên `flutter run` luôn phục vụ
web trên cùng một port:

| App | Vai trò | Port | Origin |
|---|---|---|---|
| `desktop/` | sinh viên | 54613 | http://localhost:54613 |
| `mobile/` | supervisor | 54614 | http://localhost:54614 |
| `admin_web/` | admin | 54615 | http://localhost:54615 |

Cơ chế: Flutter đọc `web_dev_config.yaml` ở thư mục app
([tài liệu Flutter](https://docs.flutter.dev/platform-integration/web/web-dev-config-file),
tính năng có từ Flutter 3.38). Cờ `--web-port` và `--web-hostname` trên dòng lệnh
vẫn ghi đè được file này.

Port cố định là cần khi app đăng nhập bằng Google trên web: origin =
scheme + host + port, và origin đó phải được khai trong **Authorized JavaScript
origins** của OAuth client trong Google Cloud Console.

## Google Sign-In trên web

`google_sign_in_web` khác native: nó **không** nhận `serverClientId` và bắt buộc
có `clientId` của một OAuth client loại Web (client_type 3). Client đó đã nằm
trong `mobile/android/app/google-services.json.example`, nên runner lấy luôn và
ghi vào `web/firebase-config.js`. Muốn dùng client khác thì đặt
`MOBILE_GOOGLE_SIGN_IN_WEB_CLIENT_ID` trong `.env` root.

Trên native, đường đăng nhập dùng `serverClientId` như cũ và không cần client id.

Một việc phải làm trong Google Cloud Console, không làm được bằng code: thêm
origin của app vào **Authorized JavaScript origins** của OAuth client đó.

Port đã cố định sẵn trong `mobile/web_dev_config.yaml`, nên `flutter run` trong
`mobile/` luôn phục vụ web ở `http://localhost:54614` và origin đó không đổi
giữa các lần chạy. Cờ `--web-port` và `--web-hostname` của dòng lệnh vẫn ghi
đè được file này.

Origin cần đăng ký là `http://localhost:54614`. Lỗi nếu quên là
`origin_mismatch` từ Google, không phải từ app.

Admin Web dùng chung Web app và OAuth client với mobile (project `srs-ai-prm`),
nên nếu Admin Web cũng đăng nhập Google thì origin của nó là
`http://localhost:54615`, đăng ký trên **cùng client đó`.

Trên web, plugin `google_sign_in_web` **không** hỗ trợ `authenticate()` (ném
`UnimplementedError`): web phải dùng nút GSI thật do Google Identity Services
dựng, và kết quả đến qua stream sự kiện. Màn đăng nhập của mobile đã xử lý
việc này: web dùng nút GSI, native vẫn dùng nút của app và `authenticate()`.

Vì port web cố định, không chạy được hai `flutter run` cùng lúc: lượt thứ hai báo
`Failed to bind web development server ... port 54614`. Dùng
`--web-port=54616` để chạy tạm song song.

Muốn Chrome dùng profile cố định, để không phải đăng nhập lại mỗi lần chạy,
dùng script sau; nó vẫn dùng đúng port đó:

```sh
cd mobile
powershell -ExecutionPolicy Bypass -File tools\dev_web.ps1
```

Các file Android `google-services.json` được sinh từ `google-services.json.example`; file thật bị ignore, template chỉ chứa tên biến. Runner giữ nguyên app ID, project ID, OAuth client và metadata khác. Các file sinh có thể chứa Firebase client key và chỉ dùng để build, không được commit.

## Chạy server

Server đọc `server/.env` làm fallback rồi đọc `.env` root, nên root có ưu tiên cao hơn. Biến môi trường triển khai có ưu tiên cao nhất. Không cần đổi cwd để server tìm thấy `.env`. Các biến Firebase của client không ảnh hưởng Settings của server.

## Giới hạn bảo mật và lịch sử Git

Firebase client API key vẫn có thể xuất hiện trong JavaScript/APK đã build. `.env` giúp tách cấu hình khỏi source; nó không biến key phía client thành secret. Quyền truy cập dữ liệu vẫn do Authentication, Security Rules và các cơ chế của Firebase quyết định. Xem [tài liệu Firebase về API keys](https://firebase.google.com/docs/projects/api-keys).

Thay đổi này bỏ literal key khỏi source hiện tại và bỏ tracking các file cấu hình local. Nó không xóa key khỏi commit cũ, không thu hồi hoặc đổi key trên Google Cloud. Với credential bí mật từng bị lộ, nhóm cần thu hồi/đổi ở nhà cung cấp; sau đó mới quyết định có cần làm sạch lịch sử Git hay không.

Đoạn `FirebaseOptions macos` được nêu trong yêu cầu không có trong working tree ở thời điểm sửa. Không thêm một key macOS chưa được app sử dụng. Nếu bổ sung nền tảng này, thêm biến client tương ứng vào allowlist và `.env.example`, rồi đọc bằng `String.fromEnvironment` như các nền tảng hiện tại.

## Kiểm tra

```sh
python -m unittest discover -s tools/tests -v
python tools/check_guardrails.py
```

Guardrail rà file đang được Git theo dõi và source chưa track nhưng không bị ignore. File đã track vẫn được rà kể cả khi có quy tắc ignore. Không đọc được danh sách Git hoặc không có input thì phải fail, không được báo pass.
