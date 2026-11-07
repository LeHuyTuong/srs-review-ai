import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:srs_review_ai_mobile/core/contracts/academic/academic_persistence.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/sync/record_change.dart';

/// Một thay đổi trong outbox, chờ server xác nhận rồi mới xoá.
class OutboxOp {
  const OutboxOp({
    required this.opId,
    required this.change,
    required this.clientTs,
    this.attempts = 0,
    this.lastError,
  });

  final String opId;
  final RecordChange change;

  /// Epoch ms lúc người dùng lưu — server dùng làm mốc last-write-wins.
  final int clientTs;
  final int attempts;
  final String? lastError;

  Map<String, Object?> toWire() => {
    'op_id': opId,
    'collection': change.collection,
    'record_id': change.recordId,
    'deleted': change.deleted,
    'data': change.deleted ? null : change.data,
    'client_ts': clientTs,
  };
}

/// SQLite trên máy — nguồn sự thật khi mất mạng.
///
/// Vì sao SQLite chứ không phải sembast (điều `AGENTS.md` khuyên cho app
/// desktop): yêu cầu của đề là SQLite; app mobile không chạy trong test runner
/// trên host nên rủi ro plugin native được chặn bằng seam — test dùng
/// `sqflite_common_ffi`, còn `flutter test` của các màn khác không bao giờ mở
/// store này (provider mặc định trả `null`).
///
/// Cần transaction: lưu snapshot và xếp outbox phải cùng thành công hoặc cùng
/// hỏng, tắt app giữa chừng không được để hai thứ lệch nhau.
class OfflineAcademicStore implements AcademicPersistence {
  OfflineAcademicStore._(this.db, {int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Database db;
  final int Function() _clock;
  int _lastTs = 0;

  static const int schemaVersion = 1;
  static const String fileName = 'srs_academic.db';

  /// Test truyền `factory` (sqflite_common_ffi) và `path` (file tạm hoặc
  /// `inMemoryDatabasePath`).
  static Future<OfflineAcademicStore> open({
    DatabaseFactory? factory,
    String? path,
    int Function()? clock,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, _) async {
          final batch = db.batch()
            ..execute('''
              CREATE TABLE academic_snapshot (
                id         INTEGER PRIMARY KEY CHECK (id = 1),
                json       TEXT NOT NULL,
                updated_at INTEGER NOT NULL
              )''')
            ..execute('''
              CREATE TABLE outbox (
                op_id      TEXT PRIMARY KEY,
                collection TEXT NOT NULL,
                record_id  TEXT NOT NULL,
                deleted    INTEGER NOT NULL DEFAULT 0,
                data       TEXT,
                client_ts  INTEGER NOT NULL,
                attempts   INTEGER NOT NULL DEFAULT 0,
                last_error TEXT
              )''')
            ..execute('CREATE INDEX idx_outbox_ts ON outbox(client_ts)')
            ..execute(
              'CREATE INDEX idx_outbox_record ON outbox(collection, record_id)',
            )
            ..execute(
              'CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          await batch.commit(noResult: true);
        },
      ),
    );
    return OfflineAcademicStore._(db, clock: clock);
  }

  Future<void> close() => db.close();

  /// Xoá dữ liệu của người dùng khi đăng xuất: bản chụp học vụ, hàng đợi
  /// chưa đồng bộ và con trỏ kéo về. Chỉ giữ `device_id` (định danh máy).
  Future<void> clearUserData() => db.transaction((tx) async {
    await tx.delete('academic_snapshot');
    await tx.delete('outbox');
    await tx.delete('sync_meta', where: 'key != ?', whereArgs: ['device_id']);
  });

  static final Random _random = Random.secure();
  static String newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Mốc thời gian tăng chặt: hai lần lưu trong cùng một ms vẫn giữ thứ tự.
  int _nextTs() => _lastTs = max(_clock(), _lastTs + 1);

  // ---------------- AcademicPersistence ----------------

  @override
  Future<AcademicJson?> restore() async {
    final rows = await db.query('academic_snapshot', where: 'id = 1');
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json']! as String) as AcademicJson;
  }

  Future<void> _saveSnapshot(DatabaseExecutor ex, AcademicSnapshot s) =>
      ex.insert('academic_snapshot', {
        'id': 1,
        'json': jsonEncode(s.data),
        'updated_at': _clock(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> committed(AcademicSnapshot before, AcademicSnapshot after) {
    final changes = diffSnapshots(before.data, after.data);
    return db.transaction((tx) async {
      await _saveSnapshot(tx, after);
      for (final change in changes) {
        await tx.insert('outbox', {
          'op_id': newId(),
          'collection': change.collection,
          'record_id': change.recordId,
          'deleted': change.deleted ? 1 : 0,
          'data': change.deleted ? null : jsonEncode(change.data),
          'client_ts': _nextTs(),
        });
      }
    });
  }

  @override
  Future<void> merged(AcademicSnapshot after) => _saveSnapshot(db, after);

  // ---------------- outbox ----------------

  Future<List<OutboxOp>> outbox({int? limit}) async {
    final rows = await db.query(
      'outbox',
      orderBy: 'client_ts ASC, rowid ASC',
      limit: limit,
    );
    return [
      for (final r in rows)
        OutboxOp(
          opId: r['op_id']! as String,
          clientTs: r['client_ts']! as int,
          attempts: r['attempts']! as int,
          lastError: r['last_error'] as String?,
          change: RecordChange(
            collection: r['collection']! as String,
            recordId: r['record_id']! as String,
            deleted: r['deleted'] == 1,
            data: r['data'] == null ? null : jsonDecode(r['data']! as String),
          ),
        ),
    ];
  }

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ??
      0;

  /// `collection/recordId` của mọi bản ghi còn thay đổi chưa gửi.
  Future<Set<String>> pendingKeys() async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT collection, record_id FROM outbox',
    );
    return {for (final r in rows) '${r['collection']}/${r['record_id']}'};
  }

  Future<void> deleteOps(Iterable<String> opIds) async {
    final ids = opIds.toList();
    if (ids.isEmpty) return;
    await db.delete(
      'outbox',
      where: 'op_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<void> recordFailure(Iterable<String> opIds, String error) async {
    final ids = opIds.toList();
    if (ids.isEmpty) return;
    await db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? '
      'WHERE op_id IN (${List.filled(ids.length, '?').join(',')})',
      [error, ...ids],
    );
  }

  // ---------------- sync_meta ----------------

  Future<String?> meta(String key) async {
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) => db.insert('sync_meta', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// ID ổn định của máy này — server dùng để phá hoà khi hai máy cùng mốc giờ.
  Future<String> deviceId() async {
    final saved = await meta('device_id');
    if (saved != null) return saved;
    final id = newId();
    await setMeta('device_id', id);
    return id;
  }
}
