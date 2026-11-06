/// Tên collection Firestore — nguồn duy nhất trong Admin Web.
///
/// Danh mục đầy đủ (path, bên ghi, bên đọc, phiên bản hợp đồng) nằm ở
/// `contracts/firestore/collections.json`. Test
/// `tools/tests/test_firestore_contract.py` khẳng định mọi tên ở đây có trong
/// danh mục, và guardrail trong `tools/check_guardrails.py` cấm viết literal
/// `.collection('...')` ngoài file này.
class FirestoreCollections {
  const FirestoreCollections._();

  /// Hồ sơ người dùng (Supervisor) do Mobile App ghi.
  static const String users = 'users';

  /// Bản mirror của Crashlytics để Admin Web đọc.
  static const String crashLogs = 'crash_logs';

  /// Metadata tệp do server FastAPI ghi qua Admin SDK (Plan 13 §2.4).
  static const String assets = 'assets';
}
