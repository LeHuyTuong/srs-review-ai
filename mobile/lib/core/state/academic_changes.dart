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
