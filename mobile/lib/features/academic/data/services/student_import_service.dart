import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'package:srs_review_ai_mobile/core/contracts/academic/student_device_gateway.dart';

// Cung cấp thao tác thiết bị qua phụ thuộc được truyền vào; Widget không tự đọc tệp hoặc sao chép.
class StudentImportService implements StudentDeviceGateway {
  @override
  Future<({String name, String? csv})?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Danh sách sinh viên',
          extensions: ['csv', 'xlsx'],
        ),
      ],
    );
    if (file == null) return null;
    // Chỉ CSV được đọc thành văn bản; XLSX trả tên tệp để ViewModel dùng dữ liệu xem trước mẫu.
    return (
      name: file.name,
      csv: file.name.toLowerCase().endsWith('.csv')
          ? await file.readAsString()
          : null,
    );
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
