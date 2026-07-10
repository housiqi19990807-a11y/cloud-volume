// Form draft for the account add/edit flow. Kept as a separate model so the
// config builder and the dialog can share it without creating an import cycle.

import 'package:remote_storage/models/remote_storage_config.dart';

/// 新增/编辑账号时提交给上层的草稿数据。
class CloudStorageAccountDraft {
  const CloudStorageAccountDraft({
    required this.storageType,
    required this.name,
    required this.mappedBucketName,
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.usePathStyle,
    required this.webdavUsername,
    required this.webdavPassword,
    this.proxyMode = 'inherit',
    this.proxyType = 'http',
    this.proxyHost = '',
    this.proxyPort = '',
    this.proxyUsername = '',
    this.proxyPassword = '',
  });

  final StorageType storageType;
  final String name;
  final String mappedBucketName;
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final bool usePathStyle;
  final String webdavUsername;
  final String webdavPassword;
  final String proxyMode;
  final String proxyType;
  final String proxyHost;
  final String proxyPort;
  final String proxyUsername;
  final String proxyPassword;
}
