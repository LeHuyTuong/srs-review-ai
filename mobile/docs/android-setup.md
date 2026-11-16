# Android foundation — 24/10/2026

> Cập nhật 25/10/2026: môi trường đã được người dùng chuyển sang `D:/Android/Sdk`, AVD `D:/Android/avd/Pixel_4a_API_34.avd`. Kiểm chứng Dashboard phase 1 dùng Pixel 4a; xem [báo cáo mới](phase1-ui-report.md). Các đường dẫn C: và Pixel_7 bên dưới là kết quả lịch sử của foundation, không phải cấu hình hiện tại.

## Công cụ

- Flutter 3.47.5 stable / Dart 3.13.4 tại D:/flutter.
- Android SDK: C:/Users/Admin/AppData/Local/Android/sdk; doctor nhận Android platform/build-tools 36.1.0.
- Đã tải bản Windows chính thức `commandlinetools-win-15859902_latest.zip` từ Google và cài **Command-line Tools 22.0** vào `cmdline-tools/latest`; xác minh bằng `sdkmanager --version` và source.properties.
- Emulator có sẵn: Pixel_7, Android 14/API 34, x86_64; khởi động bằng `flutter emulators --launch Pixel_7`.
- `flutter devices` đã nhận Android emulator tại **emulator-5554**, bên cạnh Windows/Chrome/Edge.

## Android licenses — thao tác người dùng

Lần kiểm tra sau khi cài tools: **6/8 SDK package licenses chưa chấp nhận**. Đã mở lệnh kiểm tra và trả lời `n` ở bước đề nghị review; không tự chấp nhận thay người dùng.

Mở terminal và chạy:

```powershell
flutter doctor --android-licenses
```

Chọn `y` để xem các điều khoản còn thiếu, đọc từng điều khoản và chỉ nhập `y` khi đồng ý. Sau khi hoàn tất:

```powershell
flutter doctor -v
flutter devices
flutter run -d emulator-5554
```

Doctor chỉ coi hoàn chỉnh khi Android toolchain hết cảnh báo license; chạy được một app không có nghĩa tất cả SDK package licenses đã được chấp nhận. Tools 22.0 có cảnh báo sdkmanager deprecated, nhưng lệnh license qua Flutter vẫn hoạt động và đã liệt kê số license còn thiếu.

Tham khảo: [Android Command-line Tools](https://developer.android.com/studio#command-line-tools-only), [thiết lập Android cho Flutter](https://docs.flutter.dev/platform-integration/android/setup).

## Bằng chứng chạy demo

- `flutter run -d emulator-5554` thành công: assembleDebug 260.4s, tạo `build/app/outputs/flutter-apk/app-debug.apk`, cài APK 4.1s.
- Flutter engine tải bình thường, dùng Impeller/OpenGLES; CLI đã báo Dart VM Service và đồng bộ file lên thiết bị.
- Đã chụp và xem [màn hình demo thực tế](evidence/android-demo.png): tiêu đề Flutter Demo Home Page, counter 0 và nút +; theme Inter/xanh lá đã áp dụng.
- Demo đang chạy trên emulator, chưa chuyển màn hình SRS. Đây là xác nhận build/install/render, không phải test tương tác Android tự động; thao tác tăng counter được kiểm chứng bằng Flutter widget test.
- `flutter analyze`: No issues found (8.5s); `flutter test`: cả 3 test đạt, exit code 0.
- Doctor vẫn cảnh báo license: việc chạy demo thành công không đồng nghĩa 6 license còn lại đã được chấp nhận.
