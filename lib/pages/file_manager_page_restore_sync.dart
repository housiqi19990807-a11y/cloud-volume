// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件列表恢复同步：监听回收站恢复事件，并静默刷新当前命中的对象列表缓存。

extension _FileManagerPageRestoreSync on _FileManagerPageState {
  void _handleObjectListingMutation() {
    final event = ObjectListingNotifier.instance.latestEvent;
    if (event == null || event.version <= _seenObjectListingMutationVersion) {
      return;
    }
    _seenObjectListingMutationVersion = event.version;
    if (event.kind != ObjectListingMutationKind.restored ||
        _activeBucket != event.bucket ||
        _showTrash ||
        _loading ||
        !_restoredEntriesAffectCurrentListing(event.entries)) {
      return;
    }
    unawaited(_refreshActiveObjectListingAfterRestore());
  }

  bool _restoredEntriesAffectCurrentListing(List<RestoredObjectEntry> entries) {
    if (_prefix.isEmpty) {
      return entries.isNotEmpty;
    }
    return entries.any(
      (entry) =>
          entry.objectKey == _prefix || entry.objectKey.startsWith(_prefix),
    );
  }

  Future<void> _refreshActiveObjectListingAfterRestore() async {
    final bucket = _activeBucket;
    if (bucket == null || _showTrash) {
      return;
    }
    final prefix = _prefix;
    try {
      final page = await widget.api.listObjectPage(
        _activeConfig,
        bucket,
        prefix,
        '',
        _FileManagerPageState._listPageSize,
      );
      if (!mounted ||
          _activeBucket != bucket ||
          _prefix != prefix ||
          _showTrash) {
        return;
      }
      setState(() {
        final visibleKeys = page.items.map((object) => object.key).toSet();
        _objects = page.items;
        _objectsNextToken = page.nextToken;
        _objectsHasMore = page.hasMore;
        _pagingObjects = false;
        _selectedObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
        _deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
      });
    } catch (_) {
      // 静默刷新失败不打断当前页，用户仍可手动刷新重试。
    }
  }
}
