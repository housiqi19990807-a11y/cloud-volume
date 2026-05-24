// Bootstrap state is the first app contract returned by the Go bridge.

import 'package:remote_storage/models/remote_storage_config.dart';

/// Stored profile info returned by the Go bridge.
class ProfileInfo {
  const ProfileInfo({required this.name, this.active = false});

  factory ProfileInfo.fromJson(Map<String, dynamic> json) {
    return ProfileInfo(
      name: (json['name'] ?? '').toString(),
      active: json['active'] == true,
    );
  }

  final String name;
  final bool active;
}

class BootstrapState {
  const BootstrapState({
    required this.configPath,
    required this.configured,
    required this.config,
    this.profiles = const [],
  });

  factory BootstrapState.fromJson(Map<String, dynamic> json) {
    return BootstrapState(
      configPath: (json['configPath'] ?? '').toString(),
      configured: json['configured'] == true,
      config: RemoteStorageConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      profiles: (json['profiles'] as List<dynamic>? ?? [])
          .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String configPath;
  final bool configured;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
}
