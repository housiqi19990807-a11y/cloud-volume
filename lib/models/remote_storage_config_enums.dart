// Storage configuration enums keep persisted string values in one small model.

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

enum WindowsMountEngine {
  cloudFiles('cloud_files'),
  winFsp('winfsp');

  const WindowsMountEngine(this.storageValue);

  final String storageValue;

  static WindowsMountEngine fromStorage(Object? value) {
    return value?.toString().trim().toLowerCase() == 'winfsp'
        ? WindowsMountEngine.winFsp
        : WindowsMountEngine.cloudFiles;
  }
}

enum StorageType {
  s3('s3', 'S3 对象存储'),
  webdav('webdav', 'WebDAV'),
  baiduPan('baidu_pan', '百度网盘'),
  ftp('ftp', 'FTP'),
  sftp('sftp', 'SFTP');

  const StorageType(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static StorageType fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'webdav' => StorageType.webdav,
      'baidu_pan' => StorageType.baiduPan,
      'ftp' => StorageType.ftp,
      'sftp' => StorageType.sftp,
      _ => StorageType.s3,
    };
  }
}

enum JWanFSGatewayMode {
  auto('auto', '自动探测'),
  jwanfs('jwanfs', 'JWanFS 网关'),
  genericS3('generic_s3', '通用 S3');

  const JWanFSGatewayMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  String get description {
    return switch (this) {
      JWanFSGatewayMode.auto => '连接时自动探测是否为 JWanFS 网关，以启用配额查询、服务端移动等扩展能力。',
      JWanFSGatewayMode.jwanfs => '强制启用 JWanFS 网关扩展接口（配额、服务端移动等），跳过探测。',
      JWanFSGatewayMode.genericS3 => '视为通用 S3 兼容存储，不使用 JWanFS 扩展接口。',
    };
  }

  static JWanFSGatewayMode fromStorage(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return switch (normalized) {
      'jwanfs' => JWanFSGatewayMode.jwanfs,
      'generic_s3' => JWanFSGatewayMode.genericS3,
      _ => JWanFSGatewayMode.auto,
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
