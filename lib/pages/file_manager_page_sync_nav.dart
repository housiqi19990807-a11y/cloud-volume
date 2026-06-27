part of 'file_manager_page.dart';

// 响应同步页「打开同步目录」：匹配账号+桶后进入对应前缀。

extension _FileManagerPageSyncNav on _FileManagerPageState {
  Future<void> _applyPendingSyncRemoteOpen(SyncRemoteOpenRequest request) async {
    widget.onPendingSyncRemoteOpenConsumed?.call();
    final buckets = _buckets;
    if (buckets == null || buckets.isEmpty) {
      await _loadBuckets();
    }
    if (!mounted) return;
    final list = _buckets ?? const <FileManagerBucketEntry>[];
    FileManagerBucketEntry? entry;
    for (final e in list) {
      if (e.bucket.name == request.bucket &&
          e.profileName == request.profileName) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      showAppErrorToast(
        context,
        message: '未找到同步配置对应的存储桶（${request.bucket}）',
      );
      return;
    }
    await _loadObjects(entry, request.remotePrefix);
  }
}
