// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页挂载逻辑：刷新状态，并暴露挂载、卸载和打开挂载目录动作。

extension _FileManagerPageMount on _FileManagerPageState {
  void _showMountUnavailableMessage([String? bucket]) {
    final bucketLabel = (bucket ?? _activeBucket ?? '').trim();
    final title = bucketLabel.isEmpty ? '挂载不可用' : '“$bucketLabel”暂时不能挂载';
    final message = !widget.api.capabilities.supportsMounts
        ? '当前运行环境暂不支持桌面挂载。'
        : widget.config.storageType == StorageType.baiduPan
        ? '百度网盘账号当前只支持浏览、上传、下载和对象操作，暂不支持桌面挂载。'
        : '当前账号暂不支持桌面挂载。';
    _showPageMessage(title: title, message: message);
  }

  Widget _buildContentWithMountLoading(ShadThemeData theme) {
    final content = _buildContent(theme);
    if (_mountBusyBuckets.isEmpty) {
      return content;
    }
    final color = theme.colorScheme.primary;
    return Stack(
      children: [
        content,
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.background.withValues(alpha: 0.42),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.border.withValues(alpha: 0.82),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: AppLoadingIndicator(
                          strokeWidth: 1.8,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '正在处理挂载，请稍候…',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshVisibleMountStatuses() async {
    if (!widget.api.capabilities.supportsMounts ||
        !widget.config.supportsMounts) {
      return;
    }
    if (_loading ||
        _mountStatusRefreshInFlight ||
        _mountBusyBuckets.isNotEmpty) {
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
    if (!widget.api.capabilities.supportsMounts ||
        !widget.config.supportsMounts) {
      return;
    }
    if (_activeBucket != null) {
      final activeStatus = _bucketMountStatuses[_activeBucket!];
      if (activeStatus?.mounted == true ||
          _mountBusyBuckets.contains(_activeBucket!)) {
        await _refreshMountStatus(_activeBucket!);
      }
      return;
    }
    final mountedBucket = _currentMountedBucketName();
    if (mountedBucket == null) {
      return;
    }
    await _refreshMountStatus(mountedBucket);
  }

  Future<void> _refreshBucketMountStatuses(List<BucketInfo> buckets) async {
    if (!widget.api.capabilities.supportsMounts ||
        !widget.config.supportsMounts) {
      return;
    }
    for (final bucket in buckets) {
      await _refreshMountStatus(bucket.name);
    }
  }

  Future<void> _refreshMountStatus(String bucket) async {
    if (!widget.api.capabilities.supportsMounts ||
        !widget.config.supportsMounts) {
      return;
    }
    try {
      final status = await widget.api.getBucketMountStatus(bucket);
      if (!mounted) return;
      _applyMountStatus(status);
    } catch (_) {
      // 挂载状态查询失败不阻断文件浏览；用户显式操作时再显示错误。
    }
  }

  String? _currentMountedBucketName() {
    for (final entry in _bucketMountStatuses.entries) {
      if (entry.value.mounted) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _mountBucket([String? bucket]) async {
    final targetBucket = bucket ?? _activeBucket;
    if (targetBucket == null || _mountBusyBuckets.contains(targetBucket)) {
      return;
    }
    final options = await showMountBucketDialog(context, bucket: targetBucket);
    if (options == null) {
      return;
    }
    setState(() => _mountBusyBuckets.add(targetBucket));
    try {
      final status = await widget.api.mountBucket(
        widget.config,
        targetBucket,
        options,
      );
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
    if (!widget.api.capabilities.supportsMounts ||
        !widget.config.supportsMounts) {
      return;
    }
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
