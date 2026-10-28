// Bộ nhớ tạm của demo; bộ đếm được đặt lại khi khởi động lại ứng dụng.
class DemoCounterService {
  int _value = 0;

  int read() => _value;

  void write(int value) => _value = value;
}
