import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

/// Một thay đổi ở mức bản ghi — đơn vị đồng bộ với server (`/sync/push`).
///
/// Snapshot học vụ được commit nguyên khối, nhưng đồng bộ nguyên khối thì hai
/// máy sửa hai lớp khác nhau sẽ đè mất việc của nhau. Vì vậy mỗi commit được
/// diff thành thay đổi theo `collection` + `recordId`, và server giải xung đột
/// last-write-wins theo từng bản ghi.
///
/// Khoá cấp gốc mà giá trị là danh sách bản ghi có `id` (courses, classes,
/// groups…) → mỗi phần tử là một bản ghi. Khoá còn lại (reviewState,
/// currentSemesterId…) → bản ghi trong [rootCollection] với `recordId` = tên khoá.
class RecordChange {
  const RecordChange({
    required this.collection,
    required this.recordId,
    this.deleted = false,
    this.data,
  });

  static const String rootCollection = '_root';

  final String collection;
  final String recordId;
  final bool deleted;
  final Object? data;

  String get key => '$collection/$recordId';

  @override
  String toString() => 'RecordChange($key${deleted ? ', deleted' : ''})';
}

/// Khoá không bao giờ đồng bộ: revision là bộ đếm cục bộ chống ghi đè form cũ.
const Set<String> _localOnlyKeys = {'revision'};

/// Danh sách mà mọi phần tử là Map có `id` chuỗi khác rỗng, không trùng.
bool _isRecordList(Object? value) {
  if (value is! List) return false;
  final ids = <String>{};
  for (final item in value) {
    if (item is! Map) return false;
    final id = item['id'];
    if (id is! String || id.isEmpty || !ids.add(id)) return false;
  }
  return true;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Map<String, Map> _byId(List list) => {
  for (final item in list.cast<Map>()) item['id'] as String: item,
};

/// Các thay đổi biến [before] thành [after].
List<RecordChange> diffSnapshots(AcademicJson before, AcademicJson after) {
  final changes = <RecordChange>[];
  final keys = {...before.keys, ...after.keys}..removeAll(_localOnlyKeys);
  for (final key in keys) {
    final old = before[key], next = after[key];
    if (_deepEquals(old, next)) continue;
    final oldIsList = old == null || (old is List && old.isEmpty);
    final nextIsList = next == null || (next is List && next.isEmpty);
    final recordShaped =
        (_isRecordList(old) || oldIsList) &&
        (_isRecordList(next) || nextIsList) &&
        (old is List || next is List);
    if (!recordShaped) {
      changes.add(
        RecordChange(
          collection: RecordChange.rootCollection,
          recordId: key,
          deleted: !after.containsKey(key),
          data: next,
        ),
      );
      continue;
    }
    final a = _byId(old as List? ?? const []);
    final b = _byId(next as List? ?? const []);
    for (final id in a.keys) {
      if (!b.containsKey(id)) {
        changes.add(RecordChange(collection: key, recordId: id, deleted: true));
      }
    }
    for (final entry in b.entries) {
      if (!_deepEquals(a[entry.key], entry.value)) {
        changes.add(
          RecordChange(collection: key, recordId: entry.key, data: entry.value),
        );
      }
    }
  }
  return changes;
}

/// Áp [changes] lên bản sao của [snapshot]; giữ thứ tự phần tử hiện có,
/// bản ghi mới được nối vào cuối danh sách.
AcademicJson applyChanges(
  AcademicJson snapshot,
  Iterable<RecordChange> changes,
) {
  final next = <String, dynamic>{...snapshot};
  for (final change in changes) {
    if (change.collection == RecordChange.rootCollection) {
      if (_localOnlyKeys.contains(change.recordId)) continue;
      if (change.deleted) {
        next.remove(change.recordId);
      } else {
        next[change.recordId] = change.data;
      }
      continue;
    }
    final current = next[change.collection];
    final list = [if (current is List) ...current];
    final index = list.indexWhere(
      (item) => item is Map && item['id'] == change.recordId,
    );
    if (change.deleted) {
      if (index >= 0) list.removeAt(index);
    } else if (index >= 0) {
      list[index] = change.data;
    } else {
      list.add(change.data);
    }
    next[change.collection] = list;
  }
  return next;
}
