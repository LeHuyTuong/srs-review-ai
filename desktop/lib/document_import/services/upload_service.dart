// STATUS (self-review 2026-09-14, docs/evidence/self-review-2026-09-14.md
// F1): no production caller yet — parsing is client-side today, so nothing
// needs the whole document on the server. This client + the server's
// upload:// store are tested groundwork for a future server-side parse or
// share-by-link feature. Do not assume a flow uses them; do not delete
// without the product decision recorded in F1.
/// Client for the server's presigned-upload pipeline (`uploads.py` server-side).
///
/// Why this exists: the deployment proxy (Vercel Functions) caps request
/// bodies at 4,5 MB, while the real OTES SRS is 28,7 MB — such a document can
/// never travel inline in a POST. The flow is: ask the server for a
/// capability token (presign, app-token auth), PUT the bytes to the returned
/// URL (the token in the query string IS the auth there), and reference the
/// stored object as `upload://<key>` in later requests.
///
/// Scope note: the current import flow parses the PDF locally and sends only
/// per-unit text, so nothing in the running UI needs this yet. The service is
/// the tested building block for a server-side-parse mode; wiring it into the
/// import path is a deliberate future step, not an omission.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Result of a completed upload: the reference a later request carries, plus
/// what the server says it actually stored.
class UploadOutcome {
  const UploadOutcome({
    required this.reference,
    required this.key,
    required this.sizeBytes,
    required this.sha256,
  });

  /// `upload://<key>` — the URI form the server's `resolve()` accepts.
  final String reference;
  final String key;
  final int sizeBytes;
  final String sha256;
}

class UploadService {
  UploadService(this._dio);

  final Dio _dio;

  /// Presign + PUT. Throws [DioException] on any failure (413 declared-size
  /// rejection, 403 token problems, transport errors) — callers surface it
  /// the same way the review run surfaces proxy errors.
  Future<UploadOutcome> uploadDocument({
    required Uri base,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final presign = await _dio.postUri<Map<String, dynamic>>(
      base.replace(path: '${_basePath(base)}/uploads/presign'),
      data: {'file_name': fileName, 'size_bytes': bytes.length},
    );
    final granted = presign.data!;
    // put_url is server-relative and already carries the capability token;
    // resolving it against the base is what keeps this client honest about
    // never assembling a token itself.
    final putUrl = base.resolve(granted['put_url'] as String);
    final stored = await _dio.putUri<Map<String, dynamic>>(
      putUrl,
      data: bytes,
      options: Options(contentType: 'application/octet-stream'),
    );
    final result = stored.data!;
    final key = result['key'] as String;
    return UploadOutcome(
      reference: 'upload://$key',
      key: key,
      sizeBytes: result['size'] as int,
      sha256: result['sha256'] as String,
    );
  }

  String _basePath(Uri base) => base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
}
