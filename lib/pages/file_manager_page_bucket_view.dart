part of 'file_manager_page.dart';

// 文件管理页桶列表视图：把桶级按钮和空态渲染从主页面文件中拆出。

extension _FileManagerPageBucketView on _FileManagerPageState {
  Widget _buildBucketView(ShadThemeData theme) {
    if (_buckets == null) return const SizedBox();
    final buckets = _filteredBuckets;
    if (buckets.isEmpty) {
      return FileManagerEmptyState(
        theme: theme,
        icon: LucideIcons.database,
        text: _hasSearchQuery ? '没有匹配的存储桶' : '没有可用的存储桶',
      );
    }
    return FileManagerBucketBrowser(
      buckets: buckets,
      isGrid: _isGrid,
      gridIconSize: _FileManagerPageState._bucketGridIconSize,
      listIconSize: _FileManagerPageState._listIconSize,
      onOpenBucket: (bucket) => unawaited(_navToBucket(bucket)),
      mountStatuses: _isTrashHome
          ? const <String, BucketMountStatus>{}
          : _bucketMountStatuses,
      busyBuckets: _isTrashHome ? const <String>{} : _mountBusyBuckets,
      showActionColumn: !_isTrashHome,
      onOpenTrashBucket: _isTrashHome
          ? null
          : (bucket) => unawaited(_openBucketTrash(bucket)),
      onConfigureBucket: _isTrashHome
          ? null
          : (bucket) => unawaited(_configureBucket(bucket)),
      onMountBucket: _isTrashHome
          ? null
          : widget.api.capabilities.supportsMounts
          ? (bucket) => unawaited(_mountBucket(bucket))
          : (bucket) => _showMountUnavailableMessage(bucket),
      onUnmountBucket: _isTrashHome
          ? null
          : widget.api.capabilities.supportsMounts
          ? (bucket) => unawaited(_unmountBucket(bucket))
          : null,
      onOpenMountedBucket: _isTrashHome
          ? null
          : widget.api.capabilities.supportsMounts
          ? (bucket) => unawaited(_openMountedBucket(bucket))
          : null,
      onOpenWebDavBucket: _isTrashHome
          ? null
          : widget.api.capabilities.supportsWebDavAccess
          ? (bucket) => _showWebDavEntry(bucket)
          : null,
      bucketTrashEnabled: _bucketTrashEnabled,
      webDavActionLabel: 'WebDAV',
      onReorder: (_isTrashHome || _isGrid || _hasSearchQuery)
          ? null
          : _reorderBuckets,
    );
  }

  Future<void> _reorderBuckets(int oldIndex, int newIndex) async {
    final current = List<FileManagerBucketEntry>.from(_buckets ?? const []);
    if (oldIndex < 0 || oldIndex >= current.length) {
      return;
    }
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= current.length) {
      return;
    }
    final moved = current.removeAt(oldIndex);
    current.insert(targetIndex, moved);
    setState(() => _buckets = current);
    try {
      await widget.api.reorderBuckets(
        current.map((entry) => entry.id).toList(growable: false),
      );
    } catch (error) {
      if (!mounted) return;
      showAppErrorToast(context, message: error.toString());
      unawaited(_loadBuckets());
    }
  }
}

