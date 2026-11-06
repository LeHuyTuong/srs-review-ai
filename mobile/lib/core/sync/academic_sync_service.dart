import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:srs_review_ai_mobile/core/sync/offline_academic_store.dart';
import 'package:srs_review_ai_mobile/core/sync/record_change.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/fake_academic_service.dart';

/// Kết quả một lượt đồng bộ.
enum SyncOutcome { ok, offline, rejected, signedOut, busy }

/// Phản hồi HTTP đã giải mã JSON.
class SyncResponse {
  const SyncResponse(this.status, this.body);
  final int status;
  final Object? body;
}

/// Chưa đăng nhập / không lấy được Firebase ID token.
class SyncSignedOut implements Exception {
  const SyncSignedOut();
}

/// Đường gọi server; tách ra để test thay bằng server thật trên localhost.
abstract interface class SyncTransport {
  Future<SyncResponse> get(String path, Map<String, String> query);
  Future<SyncResponse> post(String path, Object body);
  void close();
}

/// Gọi FastAPI bằng `dart:io`; Firebase ID token chỉ đi trong header.
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    required this.baseUri,
    required this.idToken,
    this.timeout = const Duration(seconds: 10),
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri baseUri;
  final Future<String?> Function() idToken;
  final Duration timeout;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}$path',
    queryParameters: query,
  );

  Future<SyncResponse> _send(
    Future<HttpClientRequest> Function() open, [
    Object? body,
  ]) async {
    final token = await idToken();
    if (token == null || token.isEmpty) throw const SyncSignedOut();
    Future<SyncResponse> run() async {
      final request = await open();
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      Object? decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = text;
      }
      return SyncResponse(response.statusCode, decoded);
    }

    return run().timeout(timeout);
  }

  @override
  Future<SyncResponse> get(String path, Map<String, String> query) =>
      _send(() => _client.getUrl(_uri(path, query)));

  @override
  Future<SyncResponse> post(String path, Object body) =>
      _send(() => _client.postUrl(_uri(path)), body);

  @override
  void close() => _client.close(force: true);
}

/// Đồng bộ outbox SQLite ↔ FastAPI (`/sync/push`, `/sync/pull`), offline-first.
///
/// 1. **Push**: outbox theo thứ tự lưu, lô ≤ [batchSize]. `op_id` làm server
///    idempotent: mất ack rồi gửi lại không áp hai lần. `accepted` /
///    `duplicate` / `stale` đều xoá khỏi outbox; `stale` (máy khác lưu SAU) thì
///    sửa snapshot local theo bản `current` của server.
/// 2. **Pull**: `since=<cursor>`, lặp tới khi hết `has_more`. Bản ghi còn thay
///    đổi local chưa gửi thì giữ bản local — đừng đè lên việc chưa đẩy lên.
/// 3. **Mất mạng**: lỗi socket/timeout/5xx → [online] = false, giữ nguyên
///    outbox, thử lại theo backoff 2s→4s→…→60s. Gọi được lại → đẩy tiếp.
class AcademicSyncService extends ChangeNotifier {
  AcademicSyncService({
    required this.store,
    required this.academic,
    required this.transport,
    this.onRemoteApplied,
    this.idleInterval = const Duration(seconds: 30),
    this.batchSize = 100,
    this.pullLimit = 500,
  });

  final OfflineAcademicStore store;
  final FakeAcademicService academic;
  final SyncTransport transport;

  /// Gọi sau khi snapshot đổi vì dữ liệu từ server, để UI tải lại.
  final void Function()? onRemoteApplied;
  final Duration idleInterval;
  final int batchSize;
  final int pullLimit;

  String? _deviceId;
  Timer? _timer;
  int _failures = 0;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  bool online = true;
  int pending = 0;
  String? lastError;
  DateTime? lastSyncAt;
  SyncOutcome? lastOutcome;

  Future<void> start() async {
    _deviceId = await store.deviceId();
    await syncNow();
  }

  /// Một lượt push + pull. Gọi chồng thì gộp: lượt đang chạy xong sẽ chạy thêm
  /// đúng một lượt nữa để không bỏ sót thay đổi vừa lưu.
  Future<SyncOutcome> syncNow() async {
    if (_disposed) return SyncOutcome.busy;
    if (_running) {
      _again = true;
      return SyncOutcome.busy;
    }
    _running = true;
    _timer?.cancel();
    SyncOutcome outcome;
    try {
      _deviceId ??= await store.deviceId();
      do {
        _again = false;
        outcome = await _guard(_pushAll);
        if (outcome == SyncOutcome.ok) outcome = await _guard(_pullAll);
      } while (_again && outcome == SyncOutcome.ok);
    } finally {
      _running = false;
    }
    if (outcome == SyncOutcome.ok) {
      _failures = 0;
      lastError = null;
      lastSyncAt = DateTime.now();
    } else if (outcome == SyncOutcome.offline ||
        outcome == SyncOutcome.rejected) {
      _failures++;
    }
    online = outcome != SyncOutcome.offline;
    lastOutcome = outcome;
    pending = await store.outboxCount();
    _schedule(outcome);
    if (!_disposed) notifyListeners();
    return outcome;
  }

  /// Thành công → nhịp nghỉ; lỗi → 2^n giây, trần 60s.
  @visibleForTesting
  Duration nextDelay(SyncOutcome outcome) => outcome == SyncOutcome.ok
      ? idleInterval
      : Duration(seconds: math.min(60, 1 << math.min(_failures, 6)));

  void _schedule(SyncOutcome outcome) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(nextDelay(outcome), () => unawaited(syncNow()));
  }

  Future<SyncOutcome> _guard(Future<SyncOutcome> Function() step) async {
    try {
      return await step();
    } on SyncSignedOut {
      lastError = 'Chưa đăng nhập — thay đổi được giữ trên máy.';
      return SyncOutcome.signedOut;
    } on SocketException catch (e) {
      lastError = 'Mất kết nối: ${e.message}';
    } on TimeoutException {
      lastError = 'Server không phản hồi.';
    } on HttpException catch (e) {
      lastError = 'Lỗi mạng: ${e.message}';
    }
    return SyncOutcome.offline;
  }

  SyncOutcome _failed(SyncResponse res, String what) {
    lastError = '$what: HTTP ${res.status} ${res.body}';
    if (res.status == 401) return SyncOutcome.signedOut;
    return res.status >= 500 ? SyncOutcome.offline : SyncOutcome.rejected;
  }

  Future<SyncOutcome> _pushAll() async {
    while (true) {
      final ops = await store.outbox(limit: batchSize);
      if (ops.isEmpty) return SyncOutcome.ok;
      final ids = ops.map((o) => o.opId).toList();
      final SyncResponse res;
      try {
        res = await transport.post('/sync/push', {
          'device_id': _deviceId,
          'ops': [for (final o in ops) o.toWire()],
        });
      } catch (e) {
        if (e is! SyncSignedOut) await store.recordFailure(ids, '$e');
        rethrow;
      }
      if (res.status != 200) {
        final outcome = _failed(res, 'Không gửi được');
        await store.recordFailure(ids, lastError!);
        return outcome;
      }
      final results = ((res.body as Map)['results'] as List)
          .cast<Map<String, dynamic>>();
      await store.deleteOps(results.map((r) => r['op_id'] as String));
      await _apply([
        for (final r in results)
          if (r['result'] != 'accepted' &&
              r['current'] is Map &&
              (r['current'] as Map)['device_id'] != _deviceId)
            _changeOf((r['current'] as Map).cast<String, dynamic>()),
      ]);
      if (ops.length < batchSize) return SyncOutcome.ok;
    }
  }

  Future<SyncOutcome> _pullAll() async {
    while (true) {
      final since = await store.meta('pull_cursor') ?? '0';
      final res = await transport.get('/sync/pull', {
        'since': since,
        'limit': '$pullLimit',
      });
      if (res.status != 200) return _failed(res, 'Không kéo được');
      final body = (res.body as Map).cast<String, dynamic>();
      await _apply([
        for (final c in (body['changes'] as List).cast<Map<String, dynamic>>())
          if (c['device_id'] != _deviceId) _changeOf(c), // máy này đã áp rồi
      ]);
      await store.setMeta('pull_cursor', '${body['cursor']}');
      if (body['has_more'] != true) return SyncOutcome.ok;
    }
  }

  static RecordChange _changeOf(Map<String, dynamic> row) => RecordChange(
    collection: row['collection'] as String,
    recordId: row['record_id'] as String,
    deleted: row['deleted'] == true,
    data: row['data'],
  );

  /// Áp thay đổi từ server, trừ bản ghi còn thay đổi local chưa gửi (việc
  /// local thắng — nó sẽ được đẩy lên và server tự giải theo last-write-wins).
  /// Kiểm pending trong chuỗi tuần tự của kho: đọc trước rồi mới merge thì một
  /// commit chen giữa sẽ bị bản server đè mất trên máy.
  Future<void> _apply(List<RecordChange> changes) async {
    if (changes.isEmpty) return;
    final merged = await academic.mergeExternal((current) async {
      final pending = await store.pendingKeys();
      final keep = [
        for (final c in changes)
          if (!pending.contains(c.key)) c,
      ];
      return keep.isEmpty ? null : applyChanges(current, keep);
    });
    if (merged != null) onRemoteApplied?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    transport.close();
    super.dispose();
  }
}
