/// The account surface: sign in, or create an account (ADR-0020).
///
/// One screen with two modes rather than two routes, because the field set is
/// nearly the same and a person who mistypes a username should not lose the
/// page they were on. The mode is an explicit switch, not a link that navigates
/// away — the app has no back stack to return through on a cold start.
///
/// Three rules this screen has to get right, each for a reason that cost
/// something to learn:
///
/// * **It never shows a spinner where a form was.** [SessionStatus.asking] is
///   the shell's business; by the time this widget builds, the answer is
///   "signed out". A form that flickered into a spinner while the user was
///   typing would discard what they typed.
/// * **The password field is obscured and NOT stored anywhere in the widget.**
///   The controller is disposed with the state, and the value is handed to the
///   view-model exactly once per submit. No "remember me" exists, and its
///   absence is deliberate — the session cookie already does that job, and a
///   second copy of a password is a second thing to leak.
/// * **The error line is the server's own sentence when there is one.** "sai
///   tên đăng nhập hoặc mật khẩu" is what a 401 means; a generic "lỗi" teaches
///   nothing. It is rendered with `ariaLive`-equivalent semantics via
///   `Semantics(liveRegion: true)` so a screen reader announces it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/role/app_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../features/workspace/view/workspace_widgets.dart';
import '../view_model/session_view_model.dart';

/// A labelled text field styled from the workspace tokens.
///
/// Written here rather than reused because the repo had NO text input widget:
/// every existing screen picks or runs, none types. Putting this in
/// `core/widgets/` would be the right home once a second screen needs it; the
/// rule is two call sites, and there is one.
class WTextField extends StatelessWidget {
  const WTextField({
    required this.label,
    required this.controller,
    this.obscure = false,
    this.hint,
    this.onSubmitted,
    this.autofocus = false,
    this.keyboardType,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final String? hint;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: AppType.dense,
            fontWeight: FontWeight.w600,
            color: colors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          obscureText: obscure,
          autofocus: autofocus,
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
          // Autocorrect and suggestions on a USERNAME are actively harmful:
          // iOS capitalises the first letter and Android may insert a space
          // after a period, both of which the server rejects with no clue.
          autocorrect: !obscure && keyboardType != TextInputType.emailAddress,
          enableSuggestions: !obscure,
          textInputAction: onSubmitted == null
              ? TextInputAction.next
              : TextInputAction.done,
          // No `AppType.body` exists — the scale stops at `button` (13) and the
          // body size comes from the theme's `bodyMedium`. Adding a token for
          // one screen would make the scale lie about how many sizes the design
          // actually has.
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: colors.muted,
            ),
            filled: true,
            fillColor: colors.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadius.boxSm,
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.boxSm,
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.boxSm,
              borderSide: BorderSide(color: colors.brand, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class AccountView extends ConsumerStatefulWidget {
  const AccountView({super.key});

  @override
  ConsumerState<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends ConsumerState<AccountView> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _classId = TextEditingController();
  final _group = TextEditingController();
  bool _registering = false;
  AppRole _role = AppRole.student;

  @override
  void initState() {
    super.initState();
    // Without these listeners the submit button NEVER enables: `_canSubmit`
    // reads the controllers, and typing into a TextField does not rebuild the
    // widget above it. Found by `account_gate_test.dart` — the test typed a
    // valid pair and the button was still disabled, which is exactly what a
    // real user would have hit. Nothing about the code looked wrong.
    _username.addListener(_onFieldChanged);
    _password.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    // setState is what makes the enabled-ness visible; the getter itself is
    // rebuilt on every frame and would otherwise be asked about stale text.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _username.removeListener(_onFieldChanged);
    _password.removeListener(_onFieldChanged);
    _username.dispose();
    _password.dispose();
    // Controllers hold the plaintext password. Disposing them is not enough to
    // erase the string from memory (Dart strings are immutable and the GC
    // decides), and claiming otherwise would be false comfort — but leaving a
    // live controller behind after the screen is gone IS avoidable, so it is
    // avoided.
    _classId.dispose();
    _group.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _username.text.trim().length >= 3 && _password.text.length >= 8;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final session = ref.read(sessionViewModelProvider.notifier);
    if (_registering) {
      await session.register(
        username: _username.text,
        password: _password.text,
        role: _role,
        classId: _role == AppRole.teacher ? _classId.text : null,
        group: _role == AppRole.student ? _group.text : null,
      );
    } else {
      await session.signIn(username: _username.text, password: _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final state = ref.watch(sessionViewModelProvider);
    final busy = state.busy;
    // A Scaffold, not a bare Center. `TextField` needs a Material ancestor for
    // its decoration and its focus highlight, and the account surface is a
    // whole screen the app hands over to — in `main.dart` it is the `home`, so
    // nothing above it provides one. A screen that assumes a host surface is a
    // screen that only renders inside one shell.
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: WPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _registering ? 'Tạo tài khoản' : 'Đăng nhập',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: AppTheme.headingFamily,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Dùng tài khoản do giảng viên cấp, hoặc tự tạo nếu bạn là '
                    'giảng viên phụ trách lớp.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  WTextField(
                    label: 'Tên đăng nhập',
                    hint: 'vd: gv01',
                    controller: _username,
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  WTextField(
                    label: 'Mật khẩu',
                    controller: _password,
                    obscure: true,
                    hint: 'ít nhất 8 ký tự',
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_registering) ...[
                    const SizedBox(height: AppSpacing.lg),
                    // The role decides WHICH membership field matters, and only
                    // one is shown: a teacher has a class, a student has a group.
                    // Showing both would invite filling in the wrong one, and the
                    // server stores them in different columns.
                    SegmentedButton<AppRole>(
                      segments: const [
                        ButtonSegment(
                          value: AppRole.student,
                          label: Text('Sinh viên'),
                        ),
                        ButtonSegment(
                          value: AppRole.teacher,
                          label: Text('Giảng viên'),
                        ),
                      ],
                      selected: {_role},
                      onSelectionChanged: (value) =>
                          setState(() => _role = value.first),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_role == AppRole.teacher)
                      WTextField(
                        label: 'Mã lớp phụ trách',
                        hint: 'vd: PRM392-SP26',
                        controller: _classId,
                      )
                    else
                      WTextField(
                        label: 'Nhóm của bạn',
                        hint: 'vd: Nhóm 1',
                        controller: _group,
                      ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: colors.attentionBg,
                          borderRadius: AppRadius.boxSm,
                          border: Border.all(color: colors.attentionBorder),
                        ),
                        child: Text(
                          state.error!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: colors.ink),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  WButton.primary(
                    label: busy
                        ? 'Đang xử lý…'
                        : _registering
                        ? 'Tạo tài khoản'
                        : 'Đăng nhập',
                    // Null while disabled, not a no-op callback: a button that
                    // looks enabled and silently does nothing is the failure mode
                    // this avoids.
                    onPressed: busy || !_canSubmit ? null : _submit,
                    expanded: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _registering = !_registering),
                    child: Text(
                      _registering
                          ? 'Đã có tài khoản? Đăng nhập'
                          : 'Chưa có tài khoản? Tạo mới',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
