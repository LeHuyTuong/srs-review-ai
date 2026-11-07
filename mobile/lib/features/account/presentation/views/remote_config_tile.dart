import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/services/remote_config_service.dart';

/// Khu vực demo Lab 3: hiện giá trị Remote Config đang áp dụng trên máy.
/// Đổi tham số trên Firebase Console → real-time update cập nhật dòng này.
class RemoteConfigTile extends ConsumerWidget {
  const RemoteConfigTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values =
        ref.watch(remoteConfigValuesProvider).value ??
        const RemoteConfigValues();
    return ListTile(
      key: const ValueKey('remote-config-tile'),
      leading: const Icon(Icons.tune_outlined),
      title: const Text('Remote Config'),
      subtitle: Text(
        'Giới hạn tải lên: ${values.maxUploadFileSizeMb} MB · '
        'Loại tệp: ${values.allowedSrsFileTypes.join(', ')}',
      ),
    );
  }
}
