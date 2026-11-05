/// Model đại diện cho log crash từ Crashlytics
class CrashLog {
  const CrashLog({
    required this.logId,
    required this.type, // 'fatal' hoặc 'non-fatal'
    required this.message,
    required this.userId,
    required this.deviceInfo,
    required this.timestamp,
    required this.stackTrace,
  });

  final String logId;
  final String type;
  final String message;
  final String userId;
  final String deviceInfo;
  final DateTime timestamp;
  final String stackTrace;

  CrashLog copyWith({
    String? logId,
    String? type,
    String? message,
    String? userId,
    String? deviceInfo,
    DateTime? timestamp,
    String? stackTrace,
  }) {
    return CrashLog(
      logId: logId ?? this.logId,
      type: type ?? this.type,
      message: message ?? this.message,
      userId: userId ?? this.userId,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      timestamp: timestamp ?? this.timestamp,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }
}
