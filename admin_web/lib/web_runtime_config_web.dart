import 'dart:js_interop';

/// Client key web do `web/firebase-config.js` gán vào `window`.
///
/// File đó do `python tools/flutter_env.py admin_web prepare` sinh ra và bị Git
/// ignore, nên client key không nằm trong source theo dõi. Nhánh này chỉ được
/// biên dịch trên web; nền tảng khác dùng file `_stub`.
@JS('firebaseApiKey')
external JSString? get _firebaseApiKey;

/// Trả về client key web lấy từ `window.firebaseApiKey`, hoặc null nếu file
/// cấu hình chưa được sinh.
String? readWebFirebaseApiKey() => _firebaseApiKey?.toDart;
