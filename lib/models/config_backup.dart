// Remote configuration backup models keep backup-only storage separate from account profiles.
import 'package:remote_storage/models/remote_storage_config.dart';

class ConfigBackupTarget {
  const ConfigBackupTarget({
    this.profileName = '',
    this.standalone,
    this.bucket = '',
    this.prefix = 'cloud-volume-config-backups',
    this.backupPassword = '',
  });

  factory ConfigBackupTarget.fromJson(Map<String, dynamic> json) {
    final standalone = json['standalone'];
    return ConfigBackupTarget(
      profileName: (json['profileName'] ?? '').toString(),
      standalone: standalone is Map<String, dynamic> && standalone.isNotEmpty
          ? RemoteStorageConfig.fromJson(standalone)
          : null,
      bucket: (json['bucket'] ?? '').toString(),
      prefix: (json['prefix'] ?? 'cloud-volume-config-backups').toString(),
      backupPassword: (json['backupPassword'] ?? '').toString(),
    );
  }

  final String profileName;
  final RemoteStorageConfig? standalone;
  final String bucket;
  final String prefix;
  final String backupPassword;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'profileName': profileName,
    'standalone': standalone?.toJson() ?? const <String, dynamic>{},
    'bucket': bucket,
    'prefix': prefix,
    'backupPassword': backupPassword,
  };

  ConfigBackupTarget copyWith({
    String? profileName,
    RemoteStorageConfig? standalone,
    bool clearStandalone = false,
    String? bucket,
    String? prefix,
    String? backupPassword,
  }) => ConfigBackupTarget(
    profileName: profileName ?? this.profileName,
    standalone: clearStandalone ? null : standalone ?? this.standalone,
    bucket: bucket ?? this.bucket,
    prefix: prefix ?? this.prefix,
    backupPassword: backupPassword ?? this.backupPassword,
  );

  /// Whether the target has a usable storage source and save location.
  bool get isReady {
    final hasSource =
        profileName.isNotEmpty || (standalone?.isConfigured ?? false);
    return hasSource && bucket.trim().isNotEmpty;
  }
}

class ConfigBackupSettings {
  const ConfigBackupSettings({
    this.enabled = false,
    this.encryptionEnabled = false,
    this.target = const ConfigBackupTarget(),
  });

  factory ConfigBackupSettings.fromJson(Map<String, dynamic> json) =>
      ConfigBackupSettings(
        enabled: json['enabled'] == true,
        encryptionEnabled: json['encryptionEnabled'] == true,
        target: ConfigBackupTarget.fromJson(
          json['target'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      );

  final bool enabled;
  final bool encryptionEnabled;
  final ConfigBackupTarget target;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'encryptionEnabled': encryptionEnabled,
    'target': target.toJson(),
  };

  ConfigBackupSettings copyWith({
    bool? enabled,
    bool? encryptionEnabled,
    ConfigBackupTarget? target,
  }) =>
      ConfigBackupSettings(
        enabled: enabled ?? this.enabled,
        encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
        target: target ?? this.target,
      );
}

class ConfigBackupSnapshot {
  const ConfigBackupSnapshot({
    required this.key,
    required this.createdAt,
    required this.size,
    required this.displayName,
  });

  factory ConfigBackupSnapshot.fromJson(Map<String, dynamic> json) =>
      ConfigBackupSnapshot(
        key: (json['key'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? '').toString(),
        size: (json['size'] ?? 0) as int,
        displayName: (json['displayName'] ?? '').toString(),
      );

  final String key;
  final String createdAt;
  final int size;
  final String displayName;
}
