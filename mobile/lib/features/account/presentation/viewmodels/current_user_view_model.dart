import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/features/account/data/repositories/current_user_repository.dart';

/// Có Firebase Auth thật hay không. Giao diện chỉ được lùi dữ liệu mẫu khi
/// không có Firebase (unit test); khi có Firebase phải hiện đúng người đăng
/// nhập hoặc trạng thái "chưa đăng nhập", không được hiện tên mẫu.
final authAvailableProvider = Provider<bool>((ref) => Firebase.apps.isNotEmpty);

/// Hồ sơ người dùng đang đăng nhập; null khi chưa đăng nhập hoặc Firebase
/// chưa khởi tạo.
final currentUserProvider = StreamProvider<CurrentUserProfile?>((ref) {
  return ref.watch(currentUserRepositoryProvider).watch();
});
