import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_theme.dart';
import 'package:srs_review_ai_admin_web/features/auth/presentation/views/admin_auth_gate.dart';

/// Điểm vào ứng dụng Web Admin dành cho Giảng viên/Quản trị viên.
/// Đồng bộ 100% Theme Tokens với Mobile App.
class SrsReviewAiWebApp extends StatelessWidget {
  const SrsReviewAiWebApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SRS Review AI - Admin Web',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AdminAuthGate(),
      );
}
