import 'package:flutter/material.dart';

// Giá trị @theme chính xác từ src/index.css của nguồn React chỉ đọc.
abstract final class AppColors {
  static const brand = Color(0xFF146B55);
  static const brandSoft = Color(0xFFEAF4ED);
  static const brandTint = Color(0xFFF2F7F3);
  static const brandHover = Color(0xFF105945);
  static const ink = Color(0xFF24332D);
  static const muted = Color(0xFF66736D);
  static const line = Color(0xFFE1E7E3);
  static const borderMuted = muted;
  static const canvas = Color(0xFFFAFBFA);
  static const subtle = Color(0xFFF7F9F7);
  static const olive = Color(0xFF637344);
  static const oliveSoft = Color(0xFFF1F4E9);
  static const amber = Color(0xFF756534);
  static const amberSoft = Color(0xFFF5F2E7);
  static const rust = Color(0xFFA65335);
  static const rustSoft = Color(0xFFFBF0EA);
  static const danger = Color(0xFFA34343);
  static const dangerSoft = Color(0xFFFAEEEE);
  // Màu trắng còn được dùng trực tiếp cho nền và chữ trong thành phần React.
  static const white = Color(0xFFFFFFFF);
}
