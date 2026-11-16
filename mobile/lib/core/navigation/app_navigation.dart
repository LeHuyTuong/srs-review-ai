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

  /// Menu cấp cao trên desktop: luôn quay về Tổng quan rồi mở đích, để bấm
  /// sidebar nhiều lần không chồng ngăn xếp vô hạn.
  static void openTopLevel(BuildContext context, String path) {
    if (ModalRoute.of(context)?.settings.name == path) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    if (path != '/dashboard') navigator.pushNamed(path);
  }
}
