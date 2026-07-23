// Builds a RemoteStorageConfig from the account form draft, preserving the
// existing secrets when the user leaves the password fields blank in edit mode.
// Extracted from the dialog so both the in-page modal and the detached
// sub-window use the same construction logic.

import 'package:remote_storage/models/cloud_storage_account_draft.dart';
import 'package:remote_storage/models/remote_storage_config.dart';

RemoteStorageConfig buildAccountConfig(
  CloudStorageAccountDraft draft, {
  RemoteStorageConfig? existing,
  RemoteStorageConfig? authorizedBaiduConfig,
}) {
  final isBaidu = draft.storageType == StorageType.baiduPan;
  final isWebdav = draft.storageType == StorageType.webdav;
  final isFTP =
      draft.storageType == StorageType.ftp ||
      draft.storageType == StorageType.sftp;

  final name = draft.name.trim();
  final fallback = isWebdav
      ? draft.webdavUsername.trim()
      : isFTP
      ? draft.ftpUsername.trim()
      : isBaidu
      ? name
      : draft.accessKey.trim();
  final label = name.isEmpty ? fallback : name;

  final mappedBucketName = draft.mappedBucketName.trim().isEmpty
      ? label
      : draft.mappedBucketName.trim();

  final baidu = authorizedBaiduConfig;

  String secretKey;
  bool hasSecretKey;
  if (isBaidu) {
    secretKey = baidu?.secretAccessKey ?? '';
    hasSecretKey = baidu?.hasSecretAccessKey ?? false;
  } else {
    // The editor intentionally does not hydrate stored secrets into Flutter.
    // A blank field therefore means "keep the stored secret", not "erase it".
    secretKey = draft.secretKey.trim().isEmpty
        ? (existing?.secretAccessKey ?? '')
        : draft.secretKey;
    hasSecretKey =
        secretKey.trim().isNotEmpty || (existing?.hasSecretAccessKey ?? false);
  }

  String webdavPassword;
  bool hasWebdavPassword;
  String webdavUsername;
  String ftpUsername;
  String ftpPassword;
  bool hasFtpPassword;
  if (isWebdav) {
    webdavUsername = draft.webdavUsername;
    webdavPassword = draft.webdavPassword.trim().isEmpty
        ? (existing?.webdavPassword ?? '')
        : draft.webdavPassword;
    hasWebdavPassword =
        webdavPassword.trim().isNotEmpty ||
        (existing?.hasWebdavPassword ?? false);
    ftpUsername = '';
    ftpPassword = '';
    hasFtpPassword = false;
  } else if (isFTP) {
    webdavUsername = '';
    webdavPassword = '';
    hasWebdavPassword = false;
    ftpUsername = draft.ftpUsername;
    ftpPassword = draft.ftpPassword.trim().isEmpty
        ? (existing?.ftpPassword ?? '')
        : draft.ftpPassword;
    hasFtpPassword =
        ftpPassword.trim().isNotEmpty || (existing?.hasFtpPassword ?? false);
  } else if (isBaidu) {
    webdavUsername = '';
    webdavPassword = '';
    hasWebdavPassword = false;
    ftpUsername = '';
    ftpPassword = '';
    hasFtpPassword = false;
  } else {
    webdavUsername = draft.accessKey;
    webdavPassword = draft.secretKey;
    hasWebdavPassword =
        draft.secretKey.trim().isNotEmpty ||
        (existing?.hasSecretAccessKey ?? false);
    ftpUsername = '';
    ftpPassword = '';
    hasFtpPassword = false;
  }

  return RemoteStorageConfig.empty().copyWith(
    storageType: draft.storageType,
    providerType: isBaidu
        ? StorageProviderType.baiduPan
        : StorageProviderType.s3,
    displayName: label,
    mappedBucketName: mappedBucketName,
    endpoint: isBaidu
        ? (baidu?.endpoint ?? 'https://pan.baidu.com')
        : draft.endpoint.trim(),
    region: draft.region.trim().isEmpty ? 'auto' : draft.region.trim(),
    accessKeyId: isBaidu ? (baidu?.accessKeyId ?? '') : draft.accessKey.trim(),
    secretAccessKey: secretKey,
    hasSecretAccessKey: hasSecretKey,
    usePathStyle: draft.usePathStyle,
    webdavUsername: webdavUsername,
    webdavPassword: webdavPassword,
    hasWebdavPassword: hasWebdavPassword,
    ftpUsername: ftpUsername,
    ftpPassword: ftpPassword,
    hasFtpPassword: hasFtpPassword,
    ftpPort: isFTP ? draft.ftpPort : 0,
    ftpAnonymous: isFTP ? draft.ftpAnonymous : false,
    proxyMode: draft.proxyMode,
    proxyType: draft.proxyType,
    proxyHost: draft.proxyHost,
    proxyPort: draft.proxyPort,
    proxyUsername: draft.proxyUsername,
    proxyPassword: draft.proxyPassword,
    bucketViews: draft.bucketViews,
  );
}
