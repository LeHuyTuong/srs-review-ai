import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_colors.dart';

// Kiểu chữ theo CSS đang áp dụng của React, tách biệt thông số bàn giao cũ.
abstract final class AppTypography {
  static const fontFamily = 'Inter';
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    wordSpacing: 0,
    height: 1.45,
    color: AppColors.ink,
  );
  // PageHeading hiện tại khác thang tiêu đề trong thông số bàn giao cũ.
  static final pageHeading = body.copyWith(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.18,
  );
  static final button = body.copyWith(fontWeight: FontWeight.w600);
  static final effectiveSmall = body.copyWith(fontWeight: FontWeight.w500);

  static final header = body.copyWith(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  static final greeting = body.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.375,
  );
  static final role = body.copyWith(color: AppColors.muted, height: 1.375);
  static final dashboardTitle = pageHeading.copyWith(height: 1.25);
  static final statValue = body.copyWith(
    fontSize: 28,
    height: 1,
    fontWeight: FontWeight.w600,
    color: AppColors.brand,
  );
  static final muted = body.copyWith(color: AppColors.muted);
  static final input = body.copyWith(fontSize: 16);
  static final courseName = body.copyWith(fontSize: 15, color: AppColors.muted);
  static final courseCode = header.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.brand,
  );
  static final ruleHeading = body.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
  static final sectionHeading = ruleHeading;
  static final disclosureArrow = strong.copyWith(fontSize: 22);
  static final strong = body.copyWith(fontWeight: FontWeight.w600);
  static final badge = body.copyWith(fontWeight: FontWeight.w500, height: 1.4);
  static final navigation = body.copyWith(height: 1.25);
  static final emptyTitle = body.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  // Giữ thông số bàn giao để truy vết; không ghi đè mức 14px trong .mobile-app.
  static final lab2PageTitle = body.copyWith(
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );
  static final sectionTitle = body.copyWith(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  static final blockTitle = body.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static final lab2BodySmall = body.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static final lab2Label = body.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  static final lab2Micro = body.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );
}
