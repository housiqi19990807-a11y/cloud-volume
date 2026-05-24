// Remote storage config models keep backend JSON shape away from page widgets.

class RemoteStorageConfig {
  const RemoteStorageConfig({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.rootPrefix,
    required this.defaultDownloadDirectory,
    required this.usePathStyle,
  });

  factory RemoteStorageConfig.empty() {
    return const RemoteStorageConfig(
      endpoint: '',
      region: '',
      bucket: '',
      accessKeyId: '',
      secretAccessKey: '',
      rootPrefix: '',
      defaultDownloadDirectory: '',
      usePathStyle: true,
    );
  }

  factory RemoteStorageConfig.fromJson(Map<String, dynamic> json) {
    return RemoteStorageConfig(
      endpoint: (json['endpoint'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      accessKeyId: (json['accessKeyId'] ?? json['access_key_id'] ?? '')
          .toString(),
      secretAccessKey:
          (json['secretAccessKey'] ?? json['secret_access_key'] ?? '')
              .toString(),
      rootPrefix: (json['rootPrefix'] ?? json['root_prefix'] ?? '').toString(),
      defaultDownloadDirectory:
          (json['defaultDownloadDirectory'] ??
                  json['default_download_directory'] ??
                  '')
              .toString(),
      usePathStyle:
          _boolFromDynamic(json['usePathStyle'] ?? json['use_path_style']) ??
          true,
    );
  }

  final String endpoint;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final String rootPrefix;
  final String defaultDownloadDirectory;
  final bool usePathStyle;

  // Bucket and rootPrefix are optional; only endpoint + auth are required.
  bool get isConfigured {
    return endpoint.trim().isNotEmpty &&
        accessKeyId.trim().isNotEmpty &&
        secretAccessKey.trim().isNotEmpty;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'endpoint': endpoint.trim(),
      'region': region.trim(),
      'bucket': bucket.trim(),
      'accessKeyId': accessKeyId.trim(),
      'secretAccessKey': secretAccessKey.trim(),
      'rootPrefix': rootPrefix.trim(),
      'defaultDownloadDirectory': defaultDownloadDirectory.trim(),
      'usePathStyle': usePathStyle,
    };
  }

  RemoteStorageConfig copyWith({
    String? endpoint,
    String? region,
    String? bucket,
    String? accessKeyId,
    String? secretAccessKey,
    String? rootPrefix,
    String? defaultDownloadDirectory,
    bool? usePathStyle,
  }) {
    return RemoteStorageConfig(
      endpoint: endpoint ?? this.endpoint,
      region: region ?? this.region,
      bucket: bucket ?? this.bucket,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      secretAccessKey: secretAccessKey ?? this.secretAccessKey,
      rootPrefix: rootPrefix ?? this.rootPrefix,
      defaultDownloadDirectory:
          defaultDownloadDirectory ?? this.defaultDownloadDirectory,
      usePathStyle: usePathStyle ?? this.usePathStyle,
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
}
