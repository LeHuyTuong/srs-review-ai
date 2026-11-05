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

Khi cần chạy Flutter trực tiếp từ IDE, chuẩn bị cấu hình trước:

```sh
python tools/flutter_env.py mobile prepare
```

Sau đó thêm `--dart-define-from-file=.dart_tool/firebase-defines.json` khi chạy từ thư mục `mobile`. Admin dùng quy trình tương tự với đối số `admin_web`. Không commit file defines đã sinh.

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
