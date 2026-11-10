import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `dart:io HttpClient()` ném `Unsupported operation: Platform._version` trên web
// ngay khi khởi tạo; dựng nó trong provider làm provider rơi vào error state
// (đã làm nút "Nộp tài liệu" chết trên web). Dùng `package:http` thay thế.
// Ngoại lệ duy nhất: sync service — provider trả null trên web trước khi tạo client.
const _allowed = {'lib/core/sync/academic_sync_service.dart'};

void main() {
  test('không file nào dựng dart:io HttpClient ngoài danh sách cho phép', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowed.contains(path)) continue;
      if (entity.readAsStringSync().contains('HttpClient(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });

  // Trên web `1 << 32` = 0 (dịch bit 32-bit) → nextInt(0) ném RangeError;
  // đã làm nút "Nộp tài liệu" chết. VM thì ra 4294967296 nên test thường không bắt.
  test('không dịch bit từ 32 trở lên (sai trên web)', () {
    final shift = RegExp(r'<<\s*(3[2-9]|[4-9]\d)');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (shift.hasMatch(entity.readAsStringSync())) offenders.add(entity.path);
    }
    expect(offenders, isEmpty);
  });
}
