/// Nền tảng không phải web: không có `window`, nên không đọc được client
/// key lúc chạy. Nhánh web dùng `web_runtime_config_web.dart`.
String? readWebFirebaseApiKey() => null;
