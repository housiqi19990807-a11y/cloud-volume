// JSON payload returned from the remote-directory picker sub-window to the main engine.

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';

class RemoteDirectoryResultPayload {
  const RemoteDirectoryResultPayload({
    required this.bucket,
    required this.prefix,
    required this.profileName,
    required this.config,
  });

  final String bucket;
  final String prefix;
  final String profileName;
  final RemoteStorageConfig config;

  factory RemoteDirectoryResultPayload.fromResult(RemoteDirectoryResult r) {
    return RemoteDirectoryResultPayload(
      bucket: r.bucket,
      prefix: r.prefix,
      profileName: r.profileName,
      config: r.config,
    );
  }

  RemoteDirectoryResult toResult() {
    return RemoteDirectoryResult(
      bucket: bucket,
      prefix: prefix,
      profileName: profileName,
      config: config,
    );
  }

  factory RemoteDirectoryResultPayload.fromJson(Map<String, dynamic> json) {
    return RemoteDirectoryResultPayload(
      bucket: json['bucket'] as String? ?? '',
      prefix: json['prefix'] as String? ?? '',
      profileName: json['profileName'] as String? ?? '',
      config: RemoteStorageConfig.fromJson(
        Map<String, dynamic>.from(json['config'] as Map? ?? {}),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bucket': bucket,
      'prefix': prefix,
      'profileName': profileName,
      'config': config.toJson(),
    };
  }
}
