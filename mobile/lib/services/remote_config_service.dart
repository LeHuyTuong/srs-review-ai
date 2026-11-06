import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const defaultMaxUploadFileSizeMb = 30;
const defaultAllowedSrsFileTypes = <String>['pdf', 'docx', 'md'];
const _supportedSrsFileTypes = {'pdf', 'docx', 'md'};

@immutable
class RemoteConfigValues {
  const RemoteConfigValues({
    this.maxUploadFileSizeMb = defaultMaxUploadFileSizeMb,
    this.allowedSrsFileTypes = defaultAllowedSrsFileTypes,
  });

  final int maxUploadFileSizeMb;
  final List<String> allowedSrsFileTypes;
}

abstract interface class RemoteConfigService {
  Future<void> initialize();

  RemoteConfigValues get values;

  Stream<RemoteConfigValues> get changes;

  void dispose();
}

/// Defaults used by widget tests and before Firebase has been initialized.
class LocalRemoteConfigService implements RemoteConfigService {
  const LocalRemoteConfigService();

  @override
  Future<void> initialize() async {}

  @override
  RemoteConfigValues get values => const RemoteConfigValues();

  @override
  Stream<RemoteConfigValues> get changes => const Stream.empty();

  @override
  void dispose() {}
}

/// Fetches and activates Remote Config without making startup depend on network.
/// Defaults are available immediately; real-time updates replace them in place.
class FirebaseRemoteConfigService implements RemoteConfigService {
  FirebaseRemoteConfigService({FirebaseRemoteConfig? remoteConfig})
    : _remoteConfig = remoteConfig ?? FirebaseRemoteConfig.instance;

  final FirebaseRemoteConfig _remoteConfig;
  final StreamController<RemoteConfigValues> _changes =
      StreamController<RemoteConfigValues>.broadcast();
  StreamSubscription<RemoteConfigUpdate>? _updateSubscription;
  Future<void>? _initialization;
  RemoteConfigValues _values = const RemoteConfigValues();

  @override
  RemoteConfigValues get values => _values;

  @override
  Stream<RemoteConfigValues> get changes => _changes.stream;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _remoteConfig.setDefaults({
        'max_upload_file_size_mb': defaultMaxUploadFileSizeMb,
        'allowed_srs_file_types': defaultAllowedSrsFileTypes.join(','),
      });
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 12),
        ),
      );
      _publish();
      _updateSubscription = _remoteConfig.onConfigUpdated.listen(
        (_) => unawaited(_activateUpdatedConfig()),
        onError: (Object error) =>
            debugPrint('Remote Config realtime update error: $error'),
      );
      unawaited(_fetchAndActivate());
    } catch (error) {
      // Offline or a temporarily unavailable Firebase service must leave the
      // local defaults usable and must not prevent the app from opening.
      debugPrint('Remote Config initialization error: $error');
      _publish();
    }
  }

  Future<void> _fetchAndActivate() async {
    try {
      await _remoteConfig.fetchAndActivate();
      _publish();
    } catch (error) {
      debugPrint('Remote Config fetch error: $error');
      _publish();
    }
  }

  Future<void> _activateUpdatedConfig() async {
    try {
      await _remoteConfig.activate();
      _publish();
    } catch (error) {
      debugPrint('Remote Config activation error: $error');
    }
  }

  void _publish() {
    final size = _remoteConfig.getInt('max_upload_file_size_mb');
    final configuredTypes = _remoteConfig
        .getString('allowed_srs_file_types')
        .split(',')
        .map((type) => type.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
        .where(_supportedSrsFileTypes.contains)
        .toSet()
        .toList(growable: false);
    _values = RemoteConfigValues(
      maxUploadFileSizeMb: size > 0 ? size : defaultMaxUploadFileSizeMb,
      allowedSrsFileTypes: configuredTypes.isEmpty
          ? defaultAllowedSrsFileTypes
          : configuredTypes,
    );
    if (!_changes.isClosed) _changes.add(_values);
  }

  @override
  void dispose() {
    unawaited(_updateSubscription?.cancel());
    unawaited(_changes.close());
  }
}

final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  final service = Firebase.apps.isEmpty
      ? const LocalRemoteConfigService()
      : FirebaseRemoteConfigService();
  ref.onDispose(service.dispose);
  return service;
});

final remoteConfigValuesProvider = StreamProvider<RemoteConfigValues>((
  ref,
) async* {
  final service = ref.watch(remoteConfigServiceProvider);
  await service.initialize();
  yield service.values;
  yield* service.changes;
});
