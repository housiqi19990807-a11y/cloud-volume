// Remote storage config models keep backend JSON shape away from page widgets.

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
  webdav('webdav', 'WebDAV');

  const StorageType(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static StorageType fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'webdav' => StorageType.webdav,
      _ => StorageType.s3,
    };
  }
}

enum StorageProviderType {
  s3('s3');

  const StorageProviderType(this.storageValue);

  final String storageValue;

  static StorageProviderType fromStorage(Object? value) {
    return StorageProviderType.s3;
  }
}

class RemoteStorageConfig {
  const RemoteStorageConfig({
    required this.endpoint,
    required this.storageType,
    required this.providerType,
    required this.displayName,
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
  final int writebackQuietSeconds;
  final bool usePathStyle;
  final WindowsMountMode windowsMountMode;
  final bool windowsThisPcEntryEnabled;
  final int windowsWritebackConcurrency;

  // Bucket and rootPrefix are optional; only endpoint + auth are required.
  bool get isConfigured {
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'endpoint': endpoint.trim(),
      'storageType': storageType.storageValue,
      'providerType': providerType.storageValue,
      'displayName': displayName.trim(),
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

  static bool? _boolFromDynamic(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }

  static int? _intFromDynamic(Object? value) {
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
