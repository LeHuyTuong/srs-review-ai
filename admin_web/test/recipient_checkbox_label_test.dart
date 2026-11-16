import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_admin_web/features/push_notifications/presentation/views/push_notifications_tab.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';
import 'package:srs_review_ai_admin_web/features/users_management/presentation/viewmodels/users_view_model.dart';

class _Users extends UsersViewModel {
  @override
  UsersState build() => UsersState(users: [
    AppUser(
      uid: 'u1', displayName: 'Nguyễn An', email: 'an@x.vn', photoUrl: null,
      registrationDate: DateTime(2026), lastSignIn: DateTime(2026),
      role: 'student',
    ),
  ]);
}

void main() {
  // Đo thật trên 8091: checkbox người nhận đọc thành "Flt semantic node 117".
  testWidgets('checkbox người nhận có nhãn đọc được', (t) async {
    t.view.physicalSize = const Size(1440, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final handle = t.ensureSemantics();
    await t.pumpWidget(ProviderScope(
      overrides: [usersViewModelProvider.overrideWith(_Users.new)],
      child: const MaterialApp(home: Scaffold(body: PushNotificationsTab())),
    ));
    await t.pump();
    expect(find.bySemanticsLabel('Chọn Nguyễn An'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Chọn tất cả')), findsWidgets);
    handle.dispose();
  });
}
