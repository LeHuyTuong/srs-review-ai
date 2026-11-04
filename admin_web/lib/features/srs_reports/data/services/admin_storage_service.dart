import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstract service for Cloud Storage operations
abstract class AdminStorageService {
  Future<List<Map<String, dynamic>>> listSrsReports();
  Future<String> getDownloadUrl(String storagePath);
  Future<void> downloadFile(String storagePath, String fileName);
}

/// Mock implementation for Admin Storage Service
class MockAdminStorageService implements AdminStorageService {
  @override
  Future<List<Map<String, dynamic>>> listSrsReports() async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Mock data
    return [
      {
        'name': 'Nhom01_SRS_Lab3.pdf',
        'fullPath': 'reports/user123/Nhom01_SRS_Lab3.pdf',
        'size': 2048576,
        'timeCreated': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'updated': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      },
      {
        'name': 'Nhom02_SRS_Final.docx',
        'fullPath': 'reports/user456/Nhom02_SRS_Final.docx',
        'size': 1536000,
        'timeCreated': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'updated': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      },
    ];
  }

  @override
  Future<String> getDownloadUrl(String storagePath) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'https://firebasestorage.googleapis.com/v0/b/srs-review-ai-ff68b.appspot.com/o/${Uri.encodeComponent(storagePath)}?alt=media';
  }

  @override
  Future<void> downloadFile(String storagePath, String fileName) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // In real implementation, would use url_launcher or download
    debugPrint('Downloading file: $fileName from $storagePath');
  }
}

/// Provider for Admin Storage Service
final adminStorageServiceProvider = Provider<AdminStorageService>((ref) {
  return MockAdminStorageService();
});
