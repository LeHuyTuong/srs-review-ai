/// Model đại diện cho tham số Remote Config
class RemoteConfigParam {
  const RemoteConfigParam({
    required this.key,
    required this.description,
    required this.currentValue,
    required this.defaultValue,
    required this.type, // 'number', 'boolean', 'string'
    this.minValue,
    this.maxValue,
  });

  final String key;
  final String description;
  final dynamic currentValue;
  final dynamic defaultValue;
  final String type;
  final num? minValue;
  final num? maxValue;

  RemoteConfigParam copyWith({
    String? key,
    String? description,
    dynamic currentValue,
    dynamic defaultValue,
    String? type,
    num? minValue,
    num? maxValue,
  }) {
    return RemoteConfigParam(
      key: key ?? this.key,
      description: description ?? this.description,
      currentValue: currentValue ?? this.currentValue,
      defaultValue: defaultValue ?? this.defaultValue,
      type: type ?? this.type,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
    );
  }
}
