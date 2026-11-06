import 'package:flutter_riverpod/flutter_riverpod.dart';

// Tín hiệu theo ProviderScope để các feature đọc làm mới sau lần ghi thành công.
// Không giữ bản sao dữ liệu và không liên kết ngược tới ViewModel của feature khác.
final academicChangesProvider = NotifierProvider<AcademicChanges, int>(
  AcademicChanges.new,
);

class AcademicChanges extends Notifier<int> {
  @override
  int build() => 0;
  void committed() => state++;
}

// Tín hiệu riêng cho thay đổi kéo từ server (đồng bộ offline). Tách khỏi
// [academicChangesProvider] vì tín hiệu đó lại kích một lượt đồng bộ — dùng
// chung thì mỗi lần kéo về lại đẩy lên, thành vòng lặp.
final academicRemoteChangesProvider =
    NotifierProvider<AcademicRemoteChanges, int>(AcademicRemoteChanges.new);

class AcademicRemoteChanges extends Notifier<int> {
  @override
  int build() => 0;
  void applied() => state++;
}
