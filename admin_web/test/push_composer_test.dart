import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_admin_web/features/push_notifications/data/repositories/push_notification_repository.dart';
import 'package:srs_review_ai_admin_web/features/push_notifications/presentation/viewmodels/push_composer_view_model.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

class _Repo implements PushNotificationRepository {
  PushMessage? last;
  Object? fail;
  @override
  Future<PushSendResult> send(PushMessage m) async {
    last = m;
    if (fail != null) throw fail!;
    return const PushSendResult(sent: 1, failed: 0, pruned: 0, noToken: ['u2']);
  }
}

AppUser _u(String id, String role) => AppUser(
  uid: id, displayName: id, email: '$id@x.vn', photoUrl: null,
  registrationDate: DateTime(2026), lastSignIn: DateTime(2026), role: role,
);

void main() {
  late _Repo repo;
  late ProviderContainer c;
  setUp(() {
    repo = _Repo();
    c = ProviderContainer(overrides: [
      pushNotificationRepositoryProvider.overrideWithValue(repo),
    ]);
  });
  tearDown(() => c.dispose());
  PushComposerViewModel vm() => c.read(pushComposerViewModelProvider.notifier);
  PushComposerState st() => c.read(pushComposerViewModelProvider);

  test('blocks until recipients, title, body and target id exist', () async {
    expect(st().blocker(), contains('người nhận'));
    vm().toggle('u1');
    expect(st().blocker(), contains('tiêu đề'));
    vm()..setTitle('T')..setBody('B')..setTarget(PushTarget.review);
    expect(st().blocker(), contains('mã'));
    expect(await vm().send(), isFalse);
    expect(repo.last, isNull, reason: 'blocked send must not hit the API');
    vm().setTargetId(' r9 ');
    expect(st().blocker(), isNull);
  });

  test('send posts trimmed message and keeps noToken in result', () async {
    vm()..toggle('u1')..toggle('u2')..setTitle(' Hi ')..setBody('Body')
      ..setTarget(PushTarget.review)..setTargetId(' r9 ');
    expect(await vm().send(), isTrue);
    expect(repo.last!.toJson(), {
      'uids': ['u1', 'u2'], 'title': 'Hi', 'body': 'Body',
      'data': {'type': 'review', 'id': 'r9'},
    });
    expect(st().result!.noToken, ['u2']);
  });

  test('error surfaces without Exception prefix', () async {
    repo.fail = Exception('Tài khoản này không có quyền gửi thông báo.');
    vm()..toggle('u1')..setTitle('T')..setBody('B');
    expect(await vm().send(), isFalse);
    expect(st().error, 'Tài khoản này không có quyền gửi thông báo.');
    expect(st().sending, isFalse);
  });

  test('role filter + select all toggles only visible users', () {
    final users = [_u('t1', 'teacher'), _u('s1', 'student'), _u('s2', 'student')];
    vm().setFilter(RecipientFilter.students);
    final visible = st().visible(users);
    expect(visible.map((u) => u.uid), ['s1', 's2']);
    vm().toggleAll(visible);
    expect(st().selected, {'s1', 's2'});
    vm().toggleAll(visible);
    expect(st().selected, isEmpty);
  });
}
