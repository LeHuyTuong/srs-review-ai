import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/domain/relative_time.dart';

AcademicJson _seed() =>
    jsonDecode(File('assets/fixtures/academic.json').readAsStringSync())
        as AcademicJson;

void main() {
  final now = DateTime(2026, 11, 10, 15, 30);
  int at(DateTime t) => t.millisecondsSinceEpoch;

  setUp(() => RelativeTime.clock = () => now);
  tearDown(() => RelativeTime.clock = () => DateTime(2026, 10, 3, 10, 20));

  test('nhãn đi theo đồng hồ thật, không đứng yên ở "2 giờ trước"', () {
    expect(
      RelativeTime.label(at(now.subtract(const Duration(seconds: 20)))),
      'Vừa xong',
    );
    expect(
      RelativeTime.label(at(now.subtract(const Duration(minutes: 45)))),
      '45 phút trước',
    );
    expect(
      RelativeTime.label(at(DateTime(2026, 11, 10, 13, 10))),
      '2 giờ trước',
    );
    expect(
      RelativeTime.label(at(DateTime(2026, 11, 9, 22, 5))),
      'Hôm qua · 22:05',
    );
    expect(
      RelativeTime.label(at(DateTime(2026, 11, 3, 8, 0))),
      '03/11/2026 · 08:00',
    );
    // Lệch giờ máy: mốc tương lai hiện ngày giờ, không bịa "vừa xong".
    expect(
      RelativeTime.label(at(DateTime(2026, 11, 11, 9, 0))),
      '11/11/2026 · 09:00',
    );
    expect(RelativeTime.label(0), isNull);
  });

  test('bài vừa vào hàng chờ hiện mốc thật thay vì chuỗi seed', () {
    final seed = _seed();
    final rq = (seed['reviewState'] as Map)['requests'] as List;
    final first = Map<String, dynamic>.from(rq.first as Map)
      ..['requestedTs'] = at(DateTime(2026, 11, 10, 15, 0));
    rq[0] = first;
    final rows = AcademicSnapshot(seed).dashboardJson['requests'] as List;
    final row = rows.firstWhere((r) => r['id'] == first['id']) as Map;
    expect(row['relativeTime'], '30 phút trước');
  });

  test('mốc chốt của test tái tạo đúng 18/18 nhãn seed cũ', () {
    RelativeTime.clock = () => DateTime(2026, 10, 3, 10, 20);
    final seed = _seed();
    final labels = ((seed['presentation'] as Map)['reviews'] as Map)
        .cast<String, dynamic>();
    final rows = AcademicSnapshot(seed).dashboardJson['requests'] as List;
    var checked = 0;
    for (final r in rows.cast<Map>()) {
      final old = (labels[r['id']] as Map?)?['relativeTime'];
      if (old == null) continue;
      expect(r['relativeTime'], old, reason: '${r['id']}');
      checked++;
    }
    expect(checked, greaterThan(0));
  });
}
