# srs_review_ai_admin_web

SRS Review AI - Admin Web (Flutter Web)

Chuẩn bị cấu hình Firebase **một lần** từ root repo, rồi trong `admin_web/` chạy
`flutter run` như bình thường, không cần cờ nào:

```sh
python tools/flutter_env.py admin_web prepare
```

Port web đã cố định ở `web_dev_config.yaml` (`http://localhost:54615`) nên origin
không đổi mỗi lần chạy.

Xem [cấu hình local](../docs/local-environment.md) để build hoặc chạy qua IDE.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
