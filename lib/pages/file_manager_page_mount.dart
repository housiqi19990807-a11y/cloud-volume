// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页挂载逻辑：刷新状态，并暴露挂载、卸载和打开挂载目录动作。

extension _FileManagerPageMount on _FileManagerPageState {
  Future<void> _refreshVisibleMountStatuses() async {
    if (_mountStatusRefreshInFlight || _mountBusyBuckets.isNotEmpty) {
      return;
    }
    _mountStatusRefreshInFlight = true;
    try {
      await _refreshVisibleMountStatusesOnce();
    } finally {
      _mountStatusRefreshInFlight = false;
    }
  }

  Future<void> _refreshVisibleMountStatusesOnce() async {
    if (_activeBucket != null) {
      await _refreshMountStatus(_activeBucket!);
      return;
    }
    await _refreshBucketMountStatuses(_buckets ?? const <BucketInfo>[]);
  }

  Future<void> _refreshBucketMountStatuses(List<BucketInfo> buckets) async {
    for (final bucket in buckets) {
      await _refreshMountStatus(bucket.name);
    }
  }

  Future<void> _refreshMountStatus(String bucket) async {
    try {
      final status = await widget.api.getBucketMountStatus(bucket);
      if (!mounted) return;
      _applyMountStatus(status);
    } catch (_) {
      // 挂载状态查询失败不阻断文件浏览；用户显式操作时再显示错误。
    }
  }

  Future<void> _mountBucket([String? bucket]) async {
    final targetBucket = bucket ?? _activeBucket;
    if (targetBucket == null || _mountBusyBuckets.contains(targetBucket)) {
      return;
    }
    setState(() => _mountBusyBuckets.add(targetBucket));
    try {
      final status = await widget.api.mountBucket(widget.config, targetBucket);
      if (!mounted) return;
      _applyMountStatus(status);
    } catch (error) {
      _showPageError(error);
    } finally {
      if (mounted) {
        setState(() => _mountBusyBuckets.remove(targetBucket));
      }
    }
  }

  Future<void> _unmountBucket([String? bucket]) async {
    final targetBucket = bucket ?? _activeBucket;
    if (targetBucket == null || _mountBusyBuckets.contains(targetBucket)) {
      return;
    }
    setState(() => _mountBusyBuckets.add(targetBucket));
    try {
      final status = await widget.api.unmountBucket(targetBucket);
      if (!mounted) return;
      _applyMountStatus(status);
    } catch (error) {
      _showPageError(error);
    } finally {
      if (mounted) {
        setState(() => _mountBusyBuckets.remove(targetBucket));
      }
    }
  }

  Future<void> _openMountedBucket([String? bucket]) async {
    final targetBucket = bucket ?? _activeBucket;
    if (targetBucket == null) return;
    try {
      final status = await widget.api.openBucketMount(targetBucket);
      if (!mounted) return;
      _applyMountStatus(status);
    } catch (error) {
      _showPageError(error);
    }
  }

  void _applyMountStatus(BucketMountStatus status) {
    if (!mounted) return;
    setState(() {
      if (status.mounted) {
        final keys = _bucketMountStatuses.keys.toList();
        for (final key in keys) {
          final existing = _bucketMountStatuses[key];
          if (existing == null || key == status.bucket) {
            continue;
          }
          _bucketMountStatuses[key] = BucketMountStatus(
            mounted: false,
            bucket: existing.bucket,
            mountPath: existing.mountPath,
            serverUrl: existing.serverUrl,
            port: existing.port,
            lastError: existing.lastError,
          );
        }
      }
      _bucketMountStatuses[status.bucket] = status;
    });
  }
}
