import 'package:flutter/material.dart';

// Giữ nguyên ô đang nhập khi provider cập nhật để không mất vị trí con trỏ.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    required this.value,
    required this.onChanged,
    required this.decoration,
    this.style,
    super.key,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chỉ đồng bộ khi giá trị ngoài khác nội dung đang nhập, như xóa hoặc khôi phục bộ lọc.
    // Khi gõ bình thường, giữ con trỏ và phần chữ đang ghép dấu.
    if (controller.text != widget.value) {
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    style: widget.style,
    decoration: widget.decoration,
    onChanged: widget.onChanged,
  );
}
