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

  final name = draft.name.trim();
  final fallback = isWebdav
      ? draft.webdavUsername.trim()
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
    secretKey = draft.secretKey;
    hasSecretKey = secretKey.trim().isNotEmpty ||
        (existing?.hasSecretAccessKey ?? false);
  }

  String webdavPassword;
  bool hasWebdavPassword;
  String webdavUsername;
  if (isWebdav) {
    webdavUsername = draft.webdavUsername;
    webdavPassword = draft.webdavPassword;
    hasWebdavPassword = webdavPassword.trim().isNotEmpty ||
        (existing?.hasWebdavPassword ?? false);
  } else if (isBaidu) {
    webdavUsername = '';
    webdavPassword = '';
    hasWebdavPassword = false;
  } else {
    webdavUsername = draft.accessKey;
    webdavPassword = draft.secretKey;
    hasWebdavPassword = draft.secretKey.trim().isNotEmpty ||
        (existing?.hasSecretAccessKey ?? false);
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
  );
}
