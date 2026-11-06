import 'dart:js_interop';

/// Client key web do `web/firebase-config.js` gán vào `window`.
///
/// File đó do `python tools/flutter_env.py mobile prepare` sinh ra và bị Git
/// ignore, nên client key không nằm trong source theo dõi. Nhánh này chỉ được
/// biên dịch trên web; nền tảng khác dùng file `_stub`.
@JS('firebaseApiKey')
external JSString? get _firebaseApiKey;

/// OAuth client id loại Web (client_type 3) cho Google Sign-In trên web.
@JS('googleSignInClientId')
external JSString? get _googleSignInClientId;

/// Trả về client key web lấy từ `window.firebaseApiKey`, hoặc null nếu file
/// cấu hình chưa được sinh.
String? readWebFirebaseApiKey() => _firebaseApiKey?.toDart;

/// Trả về OAuth client id cho Google Sign-In trên web, hoặc null nếu chưa có.
String? readWebGoogleClientId() => _googleSignInClientId?.toDart;
