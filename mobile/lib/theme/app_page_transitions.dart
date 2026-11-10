import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Chuyển trang nhẹ: fade + trượt lên 8 px, xong trong ~60% thời lượng route.
///
/// Mặc định Flutter lấy hiệu ứng theo hệ điều hành; chạy web trên macOS thì ra
/// kiểu trượt iOS cả trang kèm bóng đổ — với dashboard có sidebar cố định, mỗi
/// lần bấm menu cả khung trượt ngang trông rất giật. Bật "giảm chuyển động"
/// thì không có hiệu ứng.
class AppFadeTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadeTransitionsBuilder();

  static const _offset = Offset(0, 8);
  static const _interval = Interval(0, 0.6, curve: Curves.easeOutCubic);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final curved = CurvedAnimation(parent: animation, curve: _interval);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: _offset * (1 - curved.value),
          child: child,
        ),
      ),
    );
  }
}

/// iOS thật giữ kiểu Cupertino để còn vuốt mép trái quay lại; mọi nền tảng
/// khác (kể cả web chạy trên iPhone/macOS) dùng fade nhẹ.
PageTransitionsTheme appPageTransitionsTheme() => PageTransitionsTheme(
  builders: {
    for (final platform in TargetPlatform.values)
      platform: !kIsWeb && platform == TargetPlatform.iOS
          ? const CupertinoPageTransitionsBuilder()
          : const AppFadeTransitionsBuilder(),
  },
);
