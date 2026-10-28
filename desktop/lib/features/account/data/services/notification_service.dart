import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';

// Bao bọc nguồn thông báo mẫu; dữ liệu được giữ nguyên thứ tự và điều kiện lọc hiện có.
class NotificationService {
  const NotificationService(this.bundle);
  final AssetBundle bundle;
  Future<List<AcademicRecord>> load() async =>
      (jsonDecode(await bundle.loadString('assets/fixtures/notifications.json'))
              as List)
          .map((v) => AcademicRecord(v as AcademicJson))
          .where(
            (n) =>
                !RegExp(
                  r'(?:yêu cầu|đề nghị) tham gia (?:lớp|nhóm)|join (?:class|group) request',
                  caseSensitive: false,
                ).hasMatch(n.text('title')) &&
                !(RegExp(
                      r'tham gia|join',
                      caseSensitive: false,
                    ).hasMatch(n.text('title')) &&
                    RegExp(
                      r'lớp|nhóm|class|group',
                      caseSensitive: false,
                    ).hasMatch(n.text('title')) &&
                    RegExp(
                      r'chờ.*duyệt|chờ.*phê duyệt|yêu cầu.*duyệt|pending|awaiting approval',
                      caseSensitive: false,
                    ).hasMatch(n.text('title'))),
          )
          .toList(growable: false);
}
