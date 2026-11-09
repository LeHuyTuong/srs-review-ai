import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef SubmissionBytesFetcher = Future<Uint8List> Function(Uri uri);

/// Fetches a submitted Cloudinary document for in-app preview or sharing.
class SubmissionFileService {
  SubmissionFileService({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;
  static const maxFileBytes = 30 * 1024 * 1024;

  Future<Uint8List> fetch(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'res.cloudinary.com') {
      throw const SubmissionFileException('Link tệp không hợp lệ.');
    }
    final request = await _client.getUrl(uri);
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw SubmissionFileException(
        'Không tải được tệp (HTTP ${response.statusCode}).',
      );
    }
    if (response.contentLength > maxFileBytes) {
      await response.drain<void>();
      throw const SubmissionFileException('Tệp vượt quá giới hạn 30 MB.');
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > maxFileBytes) {
        throw const SubmissionFileException('Tệp vượt quá giới hạn 30 MB.');
      }
      builder.add(chunk);
    }
    if (length == 0) {
      throw const SubmissionFileException('Tệp tải về đang rỗng.');
    }
    return builder.takeBytes();
  }
}

final submissionBytesFetcherProvider = Provider<SubmissionBytesFetcher>(
  (ref) => SubmissionFileService().fetch,
);

class SubmissionFileException implements Exception {
  const SubmissionFileException(this.message);
  final String message;
  @override
  String toString() => message;
}
