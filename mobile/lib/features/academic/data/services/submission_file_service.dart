import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

typedef SubmissionBytesFetcher = Future<Uint8List> Function(Uri uri);

/// Fetches a submitted Cloudinary document for in-app preview or sharing.
class SubmissionFileService {
  SubmissionFileService({http.Client? client})
    : _client = client ?? http.Client();

  // package:http chạy được trên web; dart:io HttpClient thì không.
  final http.Client _client;
  static const maxFileBytes = 30 * 1024 * 1024;

  Future<Uint8List> fetch(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'res.cloudinary.com') {
      throw const SubmissionFileException('Link tệp không hợp lệ.');
    }
    final response = await _client.send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw SubmissionFileException(
        'Không tải được tệp (HTTP ${response.statusCode}).',
      );
    }
    if ((response.contentLength ?? 0) > maxFileBytes) {
      await response.stream.drain<void>();
      throw const SubmissionFileException('Tệp vượt quá giới hạn 30 MB.');
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response.stream) {
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
