// Remote storage config models keep backend JSON shape away from page widgets.

bool? _boolFromDynamic(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

int? _intFromDynamic(Object? value) {
  if (value is int) return value;
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String _normalizeTrashDirectory(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  if (trimmed.isEmpty) {
    return '.trash';
  }
  if (!trimmed.contains('/') && !trimmed.startsWith('.')) {
    return '.$trimmed';
  }
  return trimmed;
}

enum FileOpenMode {
  singleClick('single_click'),
  doubleClick('double_click');

  const FileOpenMode(this.storageValue);

  final String storageValue;

  static FileOpenMode fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'single_click' => FileOpenMode.singleClick,
      _ => FileOpenMode.singleClick,
    };
  }
}

enum WindowsMountMode {
  cloudFilesCached('cloud_files_cached'),
  cloudFilesDirect('cloud_files_direct'),
  webdav('webdav');

  const WindowsMountMode(this.storageValue);

  final String storageValue;

  static WindowsMountMode fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'cloud_files_direct' => WindowsMountMode.cloudFilesDirect,
      'webdav' => WindowsMountMode.webdav,
      _ => WindowsMountMode.cloudFilesCached,
    };
  }
}

enum StorageType {
  s3('s3', 'S3 对象存储'),
  webdav('webdav', 'WebDAV'),
  baiduPan('baidu_pan', '百度网盘');

  const StorageType(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static StorageType fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'webdav' => StorageType.webdav,
      'baidu_pan' => StorageType.baiduPan,
      _ => StorageType.s3,
    };
  }
}

enum StorageProviderType {
  s3('s3'),
  baiduPan('baidu_pan');

  const StorageProviderType(this.storageValue);

  final String storageValue;

  static StorageProviderType fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'baidu_pan' => StorageProviderType.baiduPan,
      _ => StorageProviderType.s3,
    };
  }
}

// Bucket settings let each bucket override readonly and trash behavior.
class BucketSettings {
  const BucketSettings({
    required this.readOnly,
    required this.trashEnabled,
    required this.trashDirectory,
  });

  factory BucketSettings.fromJson(Map<String, dynamic> json) {
    return BucketSettings(
      readOnly:
          _boolFromDynamic(json['readOnly'] ?? json['read_only']) ?? false,
      trashEnabled: _boolFromDynamic(
        json['trashEnabled'] ?? json['trash_enabled'],
      ),
      trashDirectory: (json['trashDirectory'] ?? json['trash_directory'] ?? '')
          .toString(),
    );
  }

  final bool readOnly;
  final bool? trashEnabled;
  final String trashDirectory;

  bool get isTrashEnabled => trashEnabled == true;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'readOnly': readOnly};
    if (trashEnabled != null) {
      result['trashEnabled'] = trashEnabled;
    }
    if (trashDirectory.trim().isNotEmpty) {
      result['trashDirectory'] = _normalizeTrashDirectory(trashDirectory);
    }
    return result;
  }

  BucketSettings copyWith({
    bool? readOnly,
    bool? trashEnabled,
    bool clearTrashEnabled = false,
    String? trashDirectory,
  }) {
    return BucketSettings(
      readOnly: readOnly ?? this.readOnly,
      trashEnabled: clearTrashEnabled
          ? null
          : (trashEnabled ?? this.trashEnabled),
      trashDirectory: trashDirectory ?? this.trashDirectory,
    );
  }
}

class RemoteStorageConfig {
  const RemoteStorageConfig({
    required this.endpoint,
    required this.storageType,
    required this.providerType,
    required this.displayName,
    required this.mappedBucketName,
    required this.region,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.hasSecretAccessKey,
    required this.webdavUsername,
    required this.webdavPassword,
    required this.hasWebdavPassword,
    required this.rootPrefix,
    required this.defaultDownloadDirectory,
    required this.cacheDirectory,
    required this.resolvedCacheDirectory,
    required this.hideDotFiles,
    required this.fileOpenMode,
    required this.trashDirectoryName,
    required this.trashRetentionDays,
    required this.bucketSettings,
    required this.writebackQuietSeconds,
    required this.usePathStyle,
    required this.windowsMountMode,
    required this.windowsThisPcEntryEnabled,
    required this.windowsWritebackConcurrency,
  });

  factory RemoteStorageConfig.empty() {
    return const RemoteStorageConfig(
      endpoint: '',
      storageType: StorageType.s3,
      providerType: StorageProviderType.s3,
      displayName: '',
      mappedBucketName: '',
      region: '',
      bucket: '',
      accessKeyId: '',
      secretAccessKey: '',
      hasSecretAccessKey: false,
      webdavUsername: '',
      webdavPassword: '',
      hasWebdavPassword: false,
      rootPrefix: '',
      defaultDownloadDirectory: '',
      cacheDirectory: '',
      resolvedCacheDirectory: '',
      hideDotFiles: true,
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: '.trash',
      trashRetentionDays: -1,
      bucketSettings: <String, BucketSettings>{},
      writebackQuietSeconds: 10,
      usePathStyle: true,
      windowsMountMode: WindowsMountMode.cloudFilesCached,
      windowsThisPcEntryEnabled: false,
      windowsWritebackConcurrency: 4,
    );
  }

  factory RemoteStorageConfig.fromJson(Map<String, dynamic> json) {
    final secretAccessKey =
        (json['secretAccessKey'] ?? json['secret_access_key'] ?? '').toString();
    final webdavPassword =
        (json['webdavPassword'] ?? json['webdav_password'] ?? '').toString();
    return RemoteStorageConfig(
      endpoint: (json['endpoint'] ?? '').toString(),
      storageType: StorageType.fromStorage(
        json['storageType'] ?? json['storage_type'],
      ),
      providerType: StorageProviderType.fromStorage(
        json['providerType'] ?? json['provider_type'],
      ),
      displayName: (json['displayName'] ?? json['display_name'] ?? '')
          .toString(),
      mappedBucketName:
          (json['mappedBucketName'] ?? json['mapped_bucket_name'] ?? '')
              .toString(),
      region: (json['region'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      accessKeyId: (json['accessKeyId'] ?? json['access_key_id'] ?? '')
          .toString(),
      secretAccessKey: secretAccessKey,
      hasSecretAccessKey:
          _boolFromDynamic(
            json['hasSecretAccessKey'] ?? json['has_secret_access_key'],
          ) ??
          secretAccessKey.trim().isNotEmpty,
      webdavUsername: (json['webdavUsername'] ?? json['webdav_username'] ?? '')
          .toString(),
      webdavPassword: webdavPassword,
      hasWebdavPassword:
          _boolFromDynamic(
            json['hasWebdavPassword'] ?? json['has_webdav_password'],
          ) ??
          webdavPassword.isNotEmpty,
      rootPrefix: (json['rootPrefix'] ?? json['root_prefix'] ?? '').toString(),
      defaultDownloadDirectory:
          (json['defaultDownloadDirectory'] ??
                  json['default_download_directory'] ??
                  '')
              .toString(),
      cacheDirectory: (json['cacheDirectory'] ?? json['cache_directory'] ?? '')
          .toString(),
      resolvedCacheDirectory:
          (json['resolvedCacheDirectory'] ??
                  json['resolved_cache_directory'] ??
                  json['cacheDirectory'] ??
                  json['cache_directory'] ??
                  '')
              .toString(),
      hideDotFiles:
          _boolFromDynamic(json['hideDotFiles'] ?? json['hide_dot_files']) ??
          true,
      fileOpenMode: FileOpenMode.fromStorage(
        json['fileOpenMode'] ?? json['file_open_mode'],
      ),
      trashDirectoryName:
          (json['trashDirectoryName'] ??
                  json['trash_directory_name'] ??
                  '.trash')
              .toString(),
      trashRetentionDays:
          _intFromDynamic(
            json['trashRetentionDays'] ?? json['trash_retention_days'],
          ) ??
          -1,
      bucketSettings: _bucketSettingsFromJson(
        json['bucketSettings'] ?? json['bucket_settings'],
      ),
      writebackQuietSeconds:
          _intFromDynamic(
            json['writebackQuietSeconds'] ?? json['writeback_quiet_seconds'],
          ) ??
          10,
      usePathStyle:
          _boolFromDynamic(json['usePathStyle'] ?? json['use_path_style']) ??
          true,
      windowsMountMode: WindowsMountMode.fromStorage(
        json['windowsMountMode'] ?? json['windows_mount_mode'],
      ),
      windowsThisPcEntryEnabled:
          _boolFromDynamic(
            json['windowsThisPcEntryEnabled'] ??
                json['windows_this_pc_entry_enabled'],
          ) ??
          true,
      windowsWritebackConcurrency:
          _intFromDynamic(
            json['windowsWritebackConcurrency'] ??
                json['windows_writeback_concurrency'],
          ) ??
          4,
    );
  }

  final String endpoint;
  final StorageType storageType;
  final StorageProviderType providerType;
  final String displayName;
  final String mappedBucketName;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final bool hasSecretAccessKey;
  final String webdavUsername;
  final String webdavPassword;
  final bool hasWebdavPassword;
  final String rootPrefix;
  final String defaultDownloadDirectory;
  final String cacheDirectory;
  final String resolvedCacheDirectory;
  final bool hideDotFiles;
  final FileOpenMode fileOpenMode;
  final String trashDirectoryName;
  final int trashRetentionDays;
  final Map<String, BucketSettings> bucketSettings;
  final int writebackQuietSeconds;
  final bool usePathStyle;
  final WindowsMountMode windowsMountMode;
  final bool windowsThisPcEntryEnabled;
  final int windowsWritebackConcurrency;

  // Bucket and rootPrefix are optional; only endpoint + auth are required.
  bool get isConfigured {
    if (storageType == StorageType.baiduPan) {
      return endpoint.trim().isNotEmpty &&
          accessKeyId.trim().isNotEmpty &&
          (secretAccessKey.trim().isNotEmpty || hasSecretAccessKey);
    }
    if (storageType == StorageType.webdav) {
      return endpoint.trim().isNotEmpty &&
          webdavUsername.trim().isNotEmpty &&
          (webdavPassword.isNotEmpty || hasWebdavPassword);
    }
    return endpoint.trim().isNotEmpty &&
        accessKeyId.trim().isNotEmpty &&
        (secretAccessKey.trim().isNotEmpty || hasSecretAccessKey);
  }

  bool get hasWebDavCredentials {
    return webdavUsername.trim().isNotEmpty &&
        (webdavPassword.isNotEmpty || hasWebdavPassword);
  }

  bool get supportsMounts => storageType != StorageType.baiduPan;

  bool get supportsShareLinks => storageType == StorageType.s3;

  BucketSettings bucketSettingsFor(String bucket) {
    final bucketName = bucket.trim();
    final defaultTrashEnabled = storageType == StorageType.s3;
    final resolved = bucketSettings[bucketName];
    return BucketSettings(
      readOnly: resolved?.readOnly ?? false,
      trashEnabled: resolved?.trashEnabled ?? defaultTrashEnabled,
      trashDirectory: resolved == null || resolved.trashDirectory.trim().isEmpty
          ? _normalizeTrashDirectory(trashDirectoryName)
          : _normalizeTrashDirectory(resolved.trashDirectory),
    );
  }

  bool bucketTrashEnabled(String bucket) =>
      bucketSettingsFor(bucket).isTrashEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'endpoint': endpoint.trim(),
      'storageType': storageType.storageValue,
      'providerType': providerType.storageValue,
      'displayName': displayName.trim(),
      'mappedBucketName': mappedBucketName.trim(),
      'region': region.trim(),
      'bucket': bucket.trim(),
      'accessKeyId': accessKeyId.trim(),
      'secretAccessKey': secretAccessKey.trim(),
      'hasSecretAccessKey': hasSecretAccessKey || secretAccessKey.isNotEmpty,
      'webdavUsername': webdavUsername.trim(),
      'webdavPassword': webdavPassword,
      'hasWebdavPassword': hasWebdavPassword || webdavPassword.isNotEmpty,
      'rootPrefix': rootPrefix.trim(),
      'defaultDownloadDirectory': defaultDownloadDirectory.trim(),
      'cacheDirectory': cacheDirectory.trim(),
      'hideDotFiles': hideDotFiles,
      'fileOpenMode': fileOpenMode.storageValue,
      'trashDirectoryName': trashDirectoryName.trim(),
      'trashRetentionDays': trashRetentionDays,
      'bucketSettings': bucketSettings.map(
        (key, value) => MapEntry(key.trim(), value.toJson()),
      ),
      'writebackQuietSeconds': writebackQuietSeconds,
      'usePathStyle': usePathStyle,
      'windowsMountMode': windowsMountMode.storageValue,
      'windowsThisPcEntryEnabled': windowsThisPcEntryEnabled,
      'windowsWritebackConcurrency': windowsWritebackConcurrency,
    };
  }

  RemoteStorageConfig copyWith({
    String? endpoint,
    StorageType? storageType,
    StorageProviderType? providerType,
    String? displayName,
    String? mappedBucketName,
    String? region,
    String? bucket,
    String? accessKeyId,
    String? secretAccessKey,
    bool? hasSecretAccessKey,
    String? webdavUsername,
    String? webdavPassword,
    bool? hasWebdavPassword,
    String? rootPrefix,
    String? defaultDownloadDirectory,
    String? cacheDirectory,
    String? resolvedCacheDirectory,
    bool? hideDotFiles,
    FileOpenMode? fileOpenMode,
    String? trashDirectoryName,
    int? trashRetentionDays,
    Map<String, BucketSettings>? bucketSettings,
    int? writebackQuietSeconds,
    bool? usePathStyle,
    WindowsMountMode? windowsMountMode,
    bool? windowsThisPcEntryEnabled,
    int? windowsWritebackConcurrency,
  }) {
    return RemoteStorageConfig(
      endpoint: endpoint ?? this.endpoint,
      storageType: storageType ?? this.storageType,
      providerType: providerType ?? this.providerType,
      displayName: displayName ?? this.displayName,
      mappedBucketName: mappedBucketName ?? this.mappedBucketName,
      region: region ?? this.region,
      bucket: bucket ?? this.bucket,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      secretAccessKey: secretAccessKey ?? this.secretAccessKey,
      hasSecretAccessKey: hasSecretAccessKey ?? this.hasSecretAccessKey,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      hasWebdavPassword: hasWebdavPassword ?? this.hasWebdavPassword,
      rootPrefix: rootPrefix ?? this.rootPrefix,
      defaultDownloadDirectory:
          defaultDownloadDirectory ?? this.defaultDownloadDirectory,
      cacheDirectory: cacheDirectory ?? this.cacheDirectory,
      resolvedCacheDirectory:
          resolvedCacheDirectory ?? this.resolvedCacheDirectory,
      hideDotFiles: hideDotFiles ?? this.hideDotFiles,
      fileOpenMode: fileOpenMode ?? this.fileOpenMode,
      trashDirectoryName: trashDirectoryName ?? this.trashDirectoryName,
      trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
      bucketSettings: bucketSettings ?? this.bucketSettings,
      writebackQuietSeconds:
          writebackQuietSeconds ?? this.writebackQuietSeconds,
      usePathStyle: usePathStyle ?? this.usePathStyle,
      windowsMountMode: windowsMountMode ?? this.windowsMountMode,
      windowsThisPcEntryEnabled:
          windowsThisPcEntryEnabled ?? this.windowsThisPcEntryEnabled,
      windowsWritebackConcurrency:
          windowsWritebackConcurrency ?? this.windowsWritebackConcurrency,
    );
  }

  static Map<String, BucketSettings> _bucketSettingsFromJson(Object? value) {
    if (value is! Map) {
      return const <String, BucketSettings>{};
    }
    final result = <String, BucketSettings>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty || entry.value is! Map) {
        continue;
      }
      result[key] = BucketSettings.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    return result;
  }
}
