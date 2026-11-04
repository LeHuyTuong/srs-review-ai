import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/srs_reports/domain/models/srs_report.dart';

/// Repository cho SRS Reports — đọc collection `srs_reports` do Mobile App ghi.
abstract class SrsReportsRepository {
  Stream<List<SrsReport>> watchReports();
  Future<String> resolveDownloadUrl(SrsReport report);
  Future<void> previewReport(SrsReport report);
  Future<void> downloadReport(SrsReport report);
}

class FirebaseSrsReportsRepository implements SrsReportsRepository {
  FirebaseSrsReportsRepository({this.firestore, this.storage});

  final FirebaseFirestore? firestore;
  final FirebaseStorage? storage;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _bucket => storage ?? FirebaseStorage.instance;

  @override
  Stream<List<SrsReport>> watchReports() => _db
      .collection('srs_reports')
      .orderBy('uploadedAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(_toReport).toList());

  @override
  Future<String> resolveDownloadUrl(SrsReport report) {
    if (report.downloadUrl.isNotEmpty) return Future.value(report.downloadUrl);
    return _bucket.ref(report.storagePath).getDownloadURL();
  }

  @override
  Future<void> previewReport(SrsReport report) async {
    final url = await resolveDownloadUrl(report);
    debugPrint('Preview ${report.fileName}: $url');
  }

  @override
  Future<void> downloadReport(SrsReport report) async {
    final url = await resolveDownloadUrl(report);
    debugPrint('Download ${report.fileName}: $url');
  }

  SrsReport _toReport(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    return SrsReport(
      id: document.id,
      fileName: (data['fileName'] as String?) ?? '(không tên)',
      fileSize: (data['fileSize'] as num?)?.toInt() ?? 0,
      uploadedBy: (data['uploadedByEmail'] as String?) ?? '',
      uploadDate: _timestamp(data['uploadedAt']) ?? DateTime.now(),
      status: (data['status'] as String?) ?? 'pending',
      storagePath: (data['storagePath'] as String?) ?? '',
      downloadUrl: (data['downloadUrl'] as String?) ?? '',
    );
  }

  DateTime? _timestamp(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
}

final srsReportsRepositoryProvider = Provider<SrsReportsRepository>((ref) {
  return FirebaseSrsReportsRepository();
});
