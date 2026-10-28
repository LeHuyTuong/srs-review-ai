import 'package:flutter/material.dart';

// Shared input primitives keep Flutter's native editing/composition behavior.
class AppTextInput extends StatelessWidget {
  const AppTextInput({
    this.controller,
    this.decoration,
    this.style,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.autofillHints,
    this.onChanged,
    super.key,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: decoration,
    style: style,
    enabled: enabled,
    obscureText: obscureText,
    keyboardType: keyboardType,
    minLines: minLines,
    maxLines: maxLines,
    autofillHints: autofillHints,
    onChanged: onChanged,
  );
}

class AppFormTextInput extends StatelessWidget {
  const AppFormTextInput({
    required this.controller,
    required this.decoration,
    required this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    super.key,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String> validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: decoration,
    validator: validator,
    keyboardType: keyboardType,
    obscureText: obscureText,
    autofillHints: autofillHints,
  );
}

Future<String?> showAppTextEntryDialog(
  BuildContext context, {
  required String title,
  required String fieldLabel,
  required String cancelLabel,
  required String confirmLabel,
}) async {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _AppTextEntryDialog(
      title: title,
      fieldLabel: fieldLabel,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AppTextEntryDialog extends StatefulWidget {
  const _AppTextEntryDialog({
    required this.title,
    required this.fieldLabel,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String fieldLabel;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_AppTextEntryDialog> createState() => _AppTextEntryDialogState();
}

class _AppTextEntryDialogState extends State<_AppTextEntryDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: AppTextInput(
      controller: controller,
      decoration: InputDecoration(labelText: widget.fieldLabel),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.cancelLabel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
