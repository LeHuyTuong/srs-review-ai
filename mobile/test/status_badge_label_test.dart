import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/widgets/app_status_tracks.dart';

import 'support/academic_fixture.dart';

void main() {
  // Danh sách Tài liệu gán status 'locked' khi khoá gửi đánh giá; badge từng
  // hiện nguyên chữ "locked" vì bảng dự phòng chỉ có key 'submissionLocked'.
  testWidgets('badge trạng thái locked hiện tiếng Việt', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppStatusBadge('locked', snapshot: academicFixture()),
        ),
      ),
    );
    expect(find.text('locked'), findsNothing);
    expect(find.text('Khóa gửi đánh giá'), findsOneWidget);
  });
}
