part of 'file_manager_page.dart';

// 响应同步页「打开同步目录」：匹配账号+桶后进入对应前缀。

extension _FileManagerPageSyncNav on _FileManagerPageState {
  void schedulePendingSyncRemoteOpen(SyncRemoteOpenRequest request) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_applyPendingSyncRemoteOpen(request));
    });
  }

  Future<void> _applyPendingSyncRemoteOpen(SyncRemoteOpenRequest request) async {
    if (_buckets == null || _buckets!.isEmpty) {
      await _loadBuckets();
    }
    if (!mounted) return;
    final list = _buckets ?? const <FileManagerBucketEntry>[];
    FileManagerBucketEntry? entry;
    for (final e in list) {
      if (e.bucket.name != request.bucket) continue;
      if (e.profileName == request.profileName) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      for (final e in list) {
        if (e.bucket.name == request.bucket) {
          entry = e;
          break;
        }
      }
    }
    if (entry == null) {
      showAppErrorToast(
        context,
        message: '未找到同步配置对应的存储桶（${request.bucket}）',
      );
      return;
    }
    final prefix = _normalizeSyncRemotePrefix(request.remotePrefix);
    final ok = await _loadObjects(entry, prefix);
    if (!mounted) return;
    if (ok) {
      widget.onPendingSyncRemoteOpenConsumed?.call();
    }
  }

  String _normalizeSyncRemotePrefix(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return '';
    p = p.replaceAll('\\', '/');
    if (!p.endsWith('/')) {
      p = '$p/';
    }
    return p;
  }
}
