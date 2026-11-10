import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/academic_persistence.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/course_contract.dart';

/// Firestore-backed academic store.
///
/// Collections (1 doc = 1 [AcademicRecord], the whole JSON of the record):
/// `courses`, `classes`, `groups`, `projects`, `registrations`, plus singleton
/// docs for the non-record parts (`_meta/snapshot` holds `revision`,
/// `currentSemesterId`, `reviewState`, `presentation`, `dashboard`, `currentUser`, …).
///
/// Seeding: when Firestore is empty (first run), [ensureSeeded] writes the
/// bundled `assets/fixtures/academic.json` seed into Firestore so later runs
/// read realtime `snapshots()` instead.
class FirebaseAcademicService {
  FirebaseAcademicService(
    FirebaseFirestore? firestore, {
    AssetBundle? bundle,
    this.syncOutbox,
  }) : _firestore = firestore,
       _bundle = bundle ?? rootBundle;

  final FirebaseFirestore? _firestore;
  final AssetBundle _bundle;

  /// Outbox SQLite đẩy lên FastAPI `/sync/push`. Ghi SAU khi Firestore nhận
  /// lượt ghi: outbox lỗi không được biến một lượt lưu đã thành công thành
  /// lỗi trên UI, nên chỉ log.
  final AcademicPersistence? syncOutbox;

  Future<void> _recordForSync(
    AcademicSnapshot before,
    AcademicSnapshot after,
  ) async {
    final outbox = syncOutbox;
    if (outbox == null) return;
    try {
      await outbox.committed(before, after);
    } catch (error) {
      debugPrint('Sync outbox write failed: $error');
    }
  }

  static const _recordCollections = <String>[
    'courses',
    'classes',
    'groups',
    'projects',
    'registrations',
  ];

  static const _metaCollections = <String>[
    'semesters',
    'offerings',
    'ruleSets',
    'students',
  ];

  /// Keys lưu thành collection; mọi key còn lại nằm trong `_meta/snapshot`.
  static const _collectionKeys = <String>[
    ..._recordCollections,
    ..._metaCollections,
  ];

  AcademicSnapshot? _lastSnapshot;
  bool _seeded = false;

  /// Firebase chưa khởi tạo (unit test): stream đóng ngay, tránh
  /// FirebaseException thô khi provider graph được dựng trong widget test.
  bool get _available => _firestore != null;

  /// Backend kiểm thử trong bộ nhớ — chỉ dùng cho unit/widget test không có
  /// Firebase. Cho phép ghi/đọc qua [AcademicSnapshot] để hành vi render có
  /// thể kiểm tra; môi trường thật vẫn phải qua Firestore.
  bool _testHooksEnabled = false;

  /// Bật backend kiểm thử (chỉ test được gọi).
  void enableTestBackend() {
    _testHooksEnabled = true;
  }

  bool get _inMemoryTestBackend => _testHooksEnabled && !_available;

  /// Kiểm thử: revision đang nằm trên server (`_meta/snapshot`). null = không
  /// mô phỏng server, claim luôn qua.
  int? serverRevisionForTest;

  static const _conflict = AcademicFailure(
    'Dữ liệu đã thay đổi. Đóng form và mở lại để tiếp tục.',
    code: AcademicErrorCode.conflict,
  );

  /// Chiếm revision kế tiếp bằng transaction trên `_meta/snapshot`.
  /// Cache của thiết bị có thể cũ (app nền, offline, listener chưa kịp về),
  /// nên so với cache thôi là để máy ghi sau đè mất reviewState máy kia vừa
  /// ghi. Mất mạng thì giữ hành vi cũ (ghi hoãn) thay vì chặn lưu offline.
  Future<void> _claimRevision(int expected, int next) async {
    if (_inMemoryTestBackend) {
      final server = serverRevisionForTest;
      if (server == null) return;
      if (server != expected) throw _conflict;
      serverRevisionForTest = next;
      return;
    }
    if (!_available) return;
    final meta = _firestore!.collection('_meta').doc('snapshot');
    var stale = false;
    try {
      await _firestore
          .runTransaction<void>((tx) async {
            final snap = await tx.get(meta);
            final server = (snap.data()?['revision'] as num?)?.toInt();
            if (snap.exists && server != null && server != expected) {
              stale = true;
              return;
            }
            tx.set(meta, {'revision': next}, SetOptions(merge: true));
          })
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Firestore revision claim deferred: $error');
    }
    if (stale) throw _conflict;
  }

  /// Kiểm thử: bơm snapshot đã dựng sẵn làm kho trong bộ nhớ.
  void injectForTest(AcademicSnapshot snapshot) {
    _testHooksEnabled = true;
    _lastSnapshot = snapshot;
  }

  /// Combined realtime stream. Seeds from the fixture on first empty read.
  Stream<AcademicSnapshot> watch() async* {
    if (!_available) {
      if (!_inMemoryTestBackend) return;
      final snapshot = await _readSeed();
      _lastSnapshot = snapshot;
      yield snapshot;
      return;
    }
    final initial = _withCurrentSupervisor(await _readSeed());
    _lastSnapshot = initial;
    yield initial;

    await ensureSeeded();
    final controllers = <String, StreamController<List<AcademicJson>>>{
      for (final name in [..._recordCollections, ..._metaCollections])
        name: StreamController<List<AcademicJson>>.broadcast(),
    };
    final latest = <String, List<AcademicJson>>{};
    final subs = <StreamSubscription<dynamic>>[];
    var metaSnapshot = await _readMeta();
    final controller = StreamController<AcademicSnapshot>();

    void emit() {
      if (latest.length < _recordCollections.length + _metaCollections.length) {
        return;
      }
      final snapshot = AcademicSnapshot({
        for (final entry in latest.entries) entry.key: entry.value,
        ...metaSnapshot,
      });
      final personalized = _withCurrentSupervisor(snapshot);
      _lastSnapshot = personalized;
      if (!controller.isClosed) controller.add(personalized);
    }

    for (final name in [..._recordCollections, ..._metaCollections]) {
      subs.add(
        _firestore!
            .collection(name)
            .snapshots()
            .listen(
              (snap) {
                latest[name] = [
                  for (final doc in snap.docs) {...doc.data(), 'id': doc.id},
                ];
                emit();
              },
              onError: (Object error) {
                debugPrint('Firestore watch($name) error: $error');
              },
            ),
      );
    }
    subs.add(
      _firestore!
          .collection('_meta')
          .doc('snapshot')
          .snapshots()
          .listen(
            (doc) async {
              metaSnapshot = await _readMeta();
              emit();
            },
            onError: (Object error) {
              debugPrint('Firestore watch(_meta) error: $error');
            },
          ),
    );

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
      for (final c in controllers.values) {
        await c.close();
      }
    };

    yield* controller.stream;
  }

  /// Gọi khi Firestore đẩy về dữ liệu mới sau lần tải đầu (máy khác ghi,
  /// hoặc lượt ghi của chính máy này được server xác nhận).
  void Function()? onRemoteChange;

  StreamSubscription<AcademicSnapshot>? _live;
  final Completer<void> _serverReady = Completer<void>();

  /// Một subscription realtime sống suốt phiên. Trước đây [load] trả fixture
  /// đóng gói và không ai nghe [watch], nên UI luôn hiện dữ liệu mẫu và mọi
  /// lượt ghi trông như biến mất sau khi tải lại.
  void _ensureLive() {
    if (_live != null) return;
    _live = watch().skip(1).listen(
      (_) {
        if (!_serverReady.isCompleted) {
          _serverReady.complete();
        } else {
          onRemoteChange?.call();
        }
      },
      onError: (Object error) =>
          debugPrint('Firestore live academic error: $error'),
    );
  }

  Future<AcademicSnapshot> load() async {
    if (_available) {
      _ensureLive();
      if (!_serverReady.isCompleted) {
        try {
          await _serverReady.future.timeout(const Duration(seconds: 8));
        } catch (error) {
          // Offline hoặc mạng chậm: dùng bản đang có, realtime sẽ cập nhật sau.
          debugPrint('Firestore academic load fallback: $error');
          if (!_serverReady.isCompleted) {
            unawaited(_serverReady.future.then((_) => onRemoteChange?.call()));
          }
        }
      }
      final cached = _lastSnapshot ?? await _readSeed();
      return _withCurrentSupervisor(cached);
    }
    return watch().first;
  }

  /// Backend kiểm thử trong bộ nhớ: đọc seed/fixture và giữ trạng thái qua các
  /// commit nhưng không gọi Firestore. Chỉ test được sử dụng.
  Future<AcademicSnapshot> _readSeed() async {
    final cached = _lastSnapshot;
    if (cached != null) return cached;
    final seed = AcademicSnapshotCodec.decode(
      jsonDecode(await _bundle.loadString('assets/fixtures/academic.json')),
    );
    return _lastSnapshot = seed;
  }

  /// Writes the fixture seed when `courses` is empty.
  Future<void> ensureSeeded() async {
    if (_inMemoryTestBackend) return;
    if (!_available) return;
    if (_seeded) return;
    _seeded = true;
    try {
      final repo = _firestore ?? FirebaseFirestore.instance;
      final empty = await repo
          .collection('courses')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 4));
      if (empty.docs.isNotEmpty) return;
      final seed = AcademicSnapshotCodec.decode(
        jsonDecode(await _bundle.loadString('assets/fixtures/academic.json')),
      );
      final seeded = _withCurrentSupervisor(seed);
      await _writeSnapshot(seeded, revision: seed.revision);
      _lastSnapshot = seeded;
    } catch (error) {
      _seeded = false;
      debugPrint('Firestore ensureSeeded skipped/deferred: $error');
    }
  }

  /// Dữ liệu mẫu mang giảng viên "Nguyễn Văn An"; khi seed lên Firestore với
  /// người đăng nhập thật, ghi đè giảng viên phụ trách bằng hồ sơ hiện tại để
  /// UI không hiển thị tên mẫu.
  AcademicSnapshot _withCurrentSupervisor(AcademicSnapshot seed) {
    if (!_available) return seed;
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      return seed;
    }
    if (user == null) return seed;
    final email = user.email?.trim() ?? '';
    final displayName = user.displayName?.trim() ?? '';
    final name = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email : '');
    if (name.isEmpty) return seed;
    final json = seed.toJson();
    for (final key in ['classes', 'projects']) {
      final rows = json[key];
      if (rows is List) {
        json[key] = [
          for (final row in rows)
            if (row is Map<String, dynamic> &&
                (row['lecturer'] as String?)?.isNotEmpty == true)
              {...row, 'lecturer': name}
            else
              row,
        ];
      }
    }
    final currentUser = json['currentUser'];
    if (currentUser is Map) {
      json['currentUser'] = {
        ...currentUser,
        'name': name,
        'email': email,
        'initials': _initialsOf(name),
      };
    }
    return AcademicSnapshot(json);
  }

  String _initialsOf(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final last = parts.last.substring(0, 1).toUpperCase();
    return parts.length > 1
        ? '${parts.first.substring(0, 1).toUpperCase()}$last'
        : last;
  }

  Future<Map<String, dynamic>> _readMeta() async {
    if (!_available) return const <String, dynamic>{};
    try {
      final doc = await _firestore!
          .collection('_meta')
          .doc('snapshot')
          .get()
          .timeout(const Duration(seconds: 4));
      return doc.data() ?? <String, dynamic>{};
    } catch (error) {
      debugPrint('Firestore _readMeta fallback: $error');
      final cached = _lastSnapshot;
      if (cached == null) return const <String, dynamic>{};
      return <String, dynamic>{
        for (final entry in cached.data.entries)
          if (!_collectionKeys.contains(entry.key)) entry.key: entry.value,
      };
    }
  }

  /// Writes a full snapshot as per-record docs (used for seed + commit).
  /// Firestore giới hạn 500 thao tác/batch nên chia lô 400.
  Future<void> _writeSnapshot(
    AcademicSnapshot snapshot, {
    int? revision,
  }) async {
    if (_inMemoryTestBackend) return;
    if (!_available) return;
    var batch = _firestore!.batch();
    var pending = 0;
    Future<void> flushIfNeeded() async {
      if (pending >= 400) {
        try {
          await _commitBatch(batch);
        } catch (error) {
          debugPrint('Firestore batch commit deferred: $error');
        }
        batch = _firestore.batch();
        pending = 0;
      }
    }

    for (final name in [..._recordCollections, ..._metaCollections]) {
      final ref = _firestore.collection(name);
      for (final record in snapshot.records(name)) {
        batch.set(ref.doc(record.id), record.toJson(), SetOptions(merge: true));
        pending++;
        await flushIfNeeded();
      }
    }
    final meta = _firestore.collection('_meta').doc('snapshot');
    final metaData = <String, dynamic>{
      for (final entry in snapshot.data.entries)
        if (!_collectionKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (revision != null) metaData['revision'] = revision;
    batch.set(meta, metaData, SetOptions(merge: true));
    try {
      await _commitBatch(batch);
    } catch (error) {
      debugPrint('Firestore batch commit deferred: $error');
    }
  }

  /// Chờ tối đa 3s để không treo UI khi offline, nhưng vẫn ghi lại kết quả
  /// thật của batch: bị rules từ chối sau timeout trước đây mất tăm.
  Future<void> _commitBatch(WriteBatch batch) {
    final done = batch.commit();
    unawaited(
      done.then(
        (_) => debugPrint('Firestore batch committed'),
        onError: (Object e) => debugPrint('Firestore batch FAILED: $e'),
      ),
    );
    return done.timeout(const Duration(seconds: 3));
  }

  /// Diffs `next` against the current snapshot and writes changed docs.
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) async {
    final current = _lastSnapshot ?? await load();
    if (current.revision != expectedRevision) {
      throw const AcademicFailure(
        'Dữ liệu đã thay đổi. Đóng form và mở lại để tiếp tục.',
        code: AcademicErrorCode.conflict,
      );
    }
    final ids = <String>{};
    final codes = <String>{};
    for (final course in next.courses) {
      CourseDto.fromJson(course.toJson());
      if (course.id.isEmpty || !ids.add(course.id)) {
        throw const AcademicFailure('ID môn học đã tồn tại hoặc không hợp lệ.');
      }
      if (!codes.add(course.code.trim().toUpperCase())) {
        throw const AcademicFailure('Mã môn đã tồn tại.');
      }
    }
    final newRevision = current.revision + 1;
    await _claimRevision(expectedRevision, newRevision);
    await _writeSnapshot(next, revision: newRevision);
    final committed = AcademicSnapshot({
      ...next.toJson(),
      'revision': newRevision,
    });
    _lastSnapshot = committed;
    await _recordForSync(current, committed);
    return committed;
  }

  /// Atomic course command via a Firestore transaction (see course_contract).
  Future<AcademicSnapshot> commitCourse(
    CourseMutation command, {
    required int expectedRevision,
  }) async {
    final current = _lastSnapshot ?? await load();
    if (current.revision != expectedRevision) {
      throw const AcademicFailure(
        'Dữ liệu đã thay đổi. Đóng form và mở lại để tiếp tục.',
        code: AcademicErrorCode.conflict,
      );
    }
    final next = command.apply(current);
    final newRevision = current.revision + 1;
    await _claimRevision(expectedRevision, newRevision);
    await _writeSnapshot(next, revision: newRevision);
    final committed = AcademicSnapshot({
      ...next.toJson(),
      'revision': newRevision,
    });
    _lastSnapshot = committed;
    await _recordForSync(current, committed);
    return committed;
  }

  /// Applies a single-doc `status` update (Luồng 1 project approval, Luồng 2 review).
  Future<AcademicSnapshot> updateDocStatus({
    required String collection,
    required String docId,
    required Map<String, dynamic> fields,
  }) async {
    if (!_available || _inMemoryTestBackend) {
      final current = _lastSnapshot;
      if (current == null) return await load();
      final rows = [
        for (final record in current.records(collection))
          if (record.id == docId)
            {...record.toJson(), ...fields}
          else
            record.toJson(),
      ];
      final updated = AcademicSnapshot({...current.toJson(), collection: rows});
      _lastSnapshot = updated;
      return updated;
    }
    try {
      await _firestore!
          .collection(collection)
          .doc(docId)
          .set({
            ...fields,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('Firestore updateDocStatus deferred: $error');
    }
    final current = _lastSnapshot;
    if (current == null) return await load();
    final rows = [
      for (final record in current.records(collection))
        if (record.id == docId)
          {...record.toJson(), ...fields}
        else
          record.toJson(),
    ];
    final updated = AcademicSnapshot({...current.toJson(), collection: rows});
    _lastSnapshot = updated;
    await _recordForSync(current, updated);
    return updated;
  }

  void dispose() {
    _lastSnapshot = null;
  }
}
