import 'dart:convert';

import 'package:flutter/services.dart';

// Đọc dữ liệu mẫu từ React hoặc nguồn học vụ được truyền vào; chưa kết nối máy chủ thật.
class FakeDashboardService {
  const FakeDashboardService(this._bundle, {this.loadData});
  final AssetBundle _bundle;
  final Future<Map<String, dynamic>> Function()? loadData;

  // Lỗi thiếu tài nguyên hoặc JSON không hợp lệ được chuyển lên Repository và ViewModel.
  Future<Map<String, dynamic>> load() async => loadData != null
      ? await loadData!()
      : jsonDecode(await _bundle.loadString('assets/fixtures/dashboard.json'))
            as Map<String, dynamic>;
}
