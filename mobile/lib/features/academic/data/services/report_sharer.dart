import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Seam cho plugin native share_plus: test thay bằng fake, View không gọi plugin.
abstract class ReportSharer {
  Future<bool> shareText({
    required String fileName,
    required String mimeType,
    required String content,
  });
}

class SharePlusReportSharer implements ReportSharer {
  @override
  Future<bool> shareText({
    required String fileName,
    required String mimeType,
    required String content,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(content),
            name: fileName,
            mimeType: mimeType,
          ),
        ],
        fileNameOverrides: [fileName],
        subject: fileName,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}

final reportSharerProvider = Provider<ReportSharer>(
  (ref) => SharePlusReportSharer(),
);
