import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/utils/web_link_launcher.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/domain/models/srs_report.dart';

/// Repository cho SRS Reports — đọc đồng thời `srs_reports`, `submissions` và join hồ sơ từ `users`.
abstract class SrsReportsRepository {
  Stream<List<SrsReport>> watchReports();
  Future<String> resolveDownloadUrl(SrsReport report);
  Future<void> previewReport(SrsReport report);
  Future<void> downloadReport(SrsReport report);
}

class FirebaseSrsReportsRepository implements SrsReportsRepository {
  FirebaseSrsReportsRepository({
    this.firestore,
    this.storage,
  });

  final FirebaseFirestore? firestore;
  final FirebaseStorage? storage;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _bucket => storage ?? FirebaseStorage.instance;

  @override
  Stream<List<SrsReport>> watchReports() {
    final controller = StreamController<List<SrsReport>>();
    var fromReports = const <SrsReport>[];
    var fromSubmissions = const <SrsReport>[];
    var userMapByUid = <String, ({String name, String email})>{};
    var userMapByEmail = <String, ({String name, String email})>{};

    void emit() {
      if (controller.isClosed) return;
      final byId = <String, SrsReport>{
        for (final sub in fromSubmissions) sub.id: sub,
        for (final rep in fromReports) rep.id: rep,
      };

      // Enrich thông tin người dùng từ collection `users` để đồng nhất 100%
      final enriched = byId.values.map((report) {
        final uidMatch = userMapByUid[report.uploaderUid];
        final emailMatch = userMapByEmail[report.uploaderEmail.toLowerCase()];
        final user = uidMatch ?? emailMatch;

        if (user != null) {
          final resolvedName = user.name.isNotEmpty
              ? user.name
              : (report.uploadedBy.isNotEmpty && !report.uploadedBy.contains('@') && report.uploadedBy.length < 20
                  ? report.uploadedBy
                  : user.email);
          final resolvedEmail = user.email.isNotEmpty ? user.email : report.uploaderEmail;
          return report.copyWith(
            uploadedBy: resolvedName,
            uploaderEmail: resolvedEmail,
          );
        }
        return report;
      }).toList()..sort((a, b) => b.uploadDate.compareTo(a.uploadDate));

      controller.add(enriched);
    }

    final subUsers = _db.collection('users').snapshots().listen((snap) {
      userMapByUid = {
        for (final doc in snap.docs)
          doc.id: (
            name: (doc.data()['displayName']?.toString() ?? '').trim(),
            email: (doc.data()['email']?.toString() ?? '').trim(),
          ),
      };
      userMapByEmail = {
        for (final entry in userMapByUid.values)
          if (entry.email.isNotEmpty)
            entry.email.toLowerCase(): entry,
      };
      emit();
    }, onError: (_) {});

    final sub1 = _db
        .collection('srs_reports')
        .orderBy('uploadedAt', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
          fromReports = snap.docs.map(_toReport).toList();
          emit();
        }, onError: controller.addError);

    final sub2 = _db
        .collection('submissions')
        .orderBy('uploaded_at', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
          fromSubmissions = snap.docs.map(_fromSubmission).toList();
          emit();
        }, onError: (_) {});

    controller.onCancel = () async {
      await subUsers.cancel();
      await sub1.cancel();
      await sub2.cancel();
    };
    return controller.stream;
  }

  @override
  Future<String> resolveDownloadUrl(SrsReport report) {
    if (report.downloadUrl.isNotEmpty) return Future.value(report.downloadUrl);
    return _bucket.ref(report.storagePath).getDownloadURL();
  }

  @override
  Future<void> previewReport(SrsReport report) async {
    final url = await resolveDownloadUrl(report);
    debugPrint('Preview ${report.fileName}: $url');
    openInNewTab(url);
  }

  @override
  Future<void> downloadReport(SrsReport report) async {
    final url = await resolveDownloadUrl(report);
    debugPrint('Download ${report.fileName}: $url');
    triggerDownload(url, report.fileName);
  }

  SrsReport _toReport(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final email = data['uploadedByEmail']?.toString().trim() ?? '';
    final name = data['uploadedByName']?.toString().trim() ??
        data['student_name']?.toString().trim() ??
        '';
    final uid = data['uploadedBy']?.toString().trim() ??
        data['uid']?.toString().trim() ??
        '';

    return SrsReport(
      id: document.id,
      fileName: data['fileName']?.toString() ?? '(không tên)',
      fileSize: (data['fileSize'] as num?)?.toInt() ?? 0,
      uploadedBy: name.isNotEmpty ? name : (email.isNotEmpty ? email : uid),
      uploaderEmail: email,
      uploaderUid: uid,
      uploadDate: _timestamp(data['uploadedAt']) ?? DateTime.now(),
      status: data['status']?.toString() ?? 'pending',
      storagePath: data['storagePath']?.toString() ?? '',
      downloadUrl: data['downloadUrl']?.toString() ?? '',
    );
  }

  SrsReport _fromSubmission(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawName = data['student_name']?.toString().trim() ?? '';
    final rawEmail = data['student_email']?.toString().trim() ?? '';
    final studentId = data['student_id']?.toString().trim() ?? '';

    String name = rawName;
    String email = rawEmail;

    if (name.contains('@') && email.isEmpty) {
      email = name;
      name = name.split('@').first;
    } else if (name.isEmpty && email.isNotEmpty) {
      name = email.split('@').first;
    } else if (name.isEmpty && studentId.isNotEmpty) {
      name = studentId.length >= 20 ? 'Sinh viên' : studentId;
    }

    return SrsReport(
      id: document.id,
      fileName: data['file_name']?.toString() ?? '(không tên)',
      fileSize: (data['file_size'] as num?)?.toInt() ?? 0,
      uploadedBy: name.isNotEmpty ? name : 'Sinh viên',
      uploaderEmail: email,
      uploaderUid: studentId,
      uploadDate: _timestamp(data['uploaded_at']) ?? DateTime.now(),
      status: 'pending',
      storagePath: data['storage_provider']?.toString() ?? 'cloudinary',
      downloadUrl: data['file_url']?.toString() ?? '',
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
