import 'package:flutter/material.dart';

// Điều hướng trong ứng dụng; giữ Tổng quan trong ngăn xếp để khôi phục bộ lọc.
abstract final class AppNavigation {
  static void open(BuildContext context, String path) {
    if (path == '/dashboard') {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (ModalRoute.of(context)?.settings.name != path) {
      Navigator.of(context).pushNamed(path);
    }
  }
}
