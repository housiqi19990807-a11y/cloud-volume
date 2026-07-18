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
