// Hợp đồng chọn tệp và sao chép để ViewModel không phụ thuộc tiện ích thiết bị.
abstract interface class StudentDeviceGateway {
  Future<({String name, String? csv})?> pick();
  Future<void> copy(String text);
}
