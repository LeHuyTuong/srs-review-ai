/// Tên collection Firestore — nguồn duy nhất trong app mobile.
///
/// Danh mục đầy đủ (path, bên ghi, bên đọc, phiên bản hợp đồng) nằm ở
/// `contracts/firestore/collections.json`. Test
/// `tools/tests/test_firestore_contract.py` khẳng định mọi tên ở đây có trong
/// danh mục, và guardrail trong `tools/check_guardrails.py` cấm viết literal
/// `.collection('...')` ngoài file này.
class FirestoreCollections {
  const FirestoreCollections._();

  /// Hồ sơ người dùng và mọi thứ thuộc về chính họ.
  static const String users = 'users';

  /// Subcollection `projects` của một user — project cá nhân (không phải
  /// project học vụ).
  static const String usersProjects = 'projects';

  /// Bản mirror của Crashlytics để Admin Web đọc.
  static const String crashLogs = 'crash_logs';

  /// Metadata tệp do server FastAPI ghi qua Admin SDK (Plan 13 §2.4).
  static const String assets = 'assets';
}
