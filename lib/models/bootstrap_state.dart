// Bootstrap state is the first app contract returned by the Go bridge.

import 'package:remote_storage/models/remote_storage_config.dart';

class BootstrapState {
  const BootstrapState({
    required this.configPath,
    required this.configured,
    required this.config,
  });

  factory BootstrapState.fromJson(Map<String, dynamic> json) {
    return BootstrapState(
      configPath: (json['configPath'] ?? '').toString(),
      configured: json['configured'] == true,
      config: RemoteStorageConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }

  final String configPath;
  final bool configured;
  final RemoteStorageConfig config;
}
