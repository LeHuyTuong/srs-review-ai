/// Every modal in this app opens as a FULL-SCREEN surface.
///
/// Why this file exists (2026-09-25): the document preview arrived as a ~610dp
/// card floating in the middle of a 1224dp window — "một mẩu giữa" — and the
/// request was that it, and every other modal, fill the screen. Twelve modals
/// went through one `_show()` helper and three more called `showDialog`
/// directly, so a single entry point is the only way "full-screen" stays true
/// as modals are added later.
library;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/workspace_colors.dart';

/// Opens [builder] full-screen and returns whatever it pops with.
///
/// The route deliberately does NOT build a `Dialog`. `Dialog` wraps its child
/// in `IntrinsicWidth`, which fights a flex column that owns the whole screen —
/// exactly what the preview's page viewer is, since it has to fill the height
/// left under the header. `showDialog` already supplies the barrier, the route
/// semantics and the SafeArea, which is all this needs.
///
/// The `Material` is not decoration. A route's content sits beside the home
/// `Scaffold`, not inside it, so nothing above it provides a Material — and
/// `TextField`, `IconButton` and `WButton` all assert one. A `ColoredBox` here
/// cost three widget tests (every field in a form vanished with 19 "No
/// Material widget found" exceptions) before the ancestor was added back.
Future<T?> showFullScreenSurface<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  barrierDismissible: true,
  builder: (dialogContext) => Material(
    color: dialogContext.workspaceColors.canvas,
    child: builder(dialogContext),
  ),
);

/// The chrome every full-screen modal shares: a header (icon, title,
/// description, optional actions, close) over a body that owns the rest of the
/// height.
class WFullScreenSurface extends StatelessWidget {
  const WFullScreenSurface({
    required this.icon,
    required this.title,
    required this.description,
    required this.body,
    this.actions = const [],
    this.maxContentWidth = 980,
    this.fillBody = false,
    this.centerBody = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget body;
  final List<Widget> actions;

  /// Measure cap for a text-heavy body. The SURFACE is always full-screen; this
  /// only stops a paragraph of Vietnamese from stretching across a 1900px
  /// window. [fillBody] opts out entirely — the preview shows a page, not prose.
  final double maxContentWidth;

  /// The body takes the remaining height instead of being sized by its own
  /// content. The preview's page viewer needs this: a 520dp-capped image box
  /// was the reason a 217-page document previewed as a small picture in a
  /// little card.
  final bool fillBody;

  /// Vertically centre the body — for the short confirmation surfaces.
  final bool centerBody;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxxl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 49,
                height: 49,
                decoration: BoxDecoration(
                  color: colors.sageBg,
                  borderRadius: AppRadius.boxMd,
                  border: Border.all(color: colors.border),
                ),
                child: Icon(icon, color: colors.sage, size: 25),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              ...actions,
              IconButton(
                tooltip: 'Đóng',
                icon: const Icon(Icons.close),
                color: colors.muted,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: fillBody
              ? body
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxxl,
                    AppSpacing.xl,
                    AppSpacing.xxxl,
                    AppSpacing.huge,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: centerBody ? Center(child: body) : body,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
