part of 'file_manager_page.dart';

// 文件管理页派生状态：把筛选和当前视图相关计算单独拆出，避免主文件过长。

extension _FileManagerPageDerivedState on _FileManagerPageState {
  BucketMountStatus? get _activeMountStatus =>
      _activeBucket == null ? null : _bucketMountStatuses[_activeBucket!];

  bool get _isTrashHome => widget.homeView == FileManagerHomeView.trash;

  bool get _hasSearchQuery => _searchText.isNotEmpty;

  List<BucketInfo> get _filteredBuckets {
    final buckets = _buckets ?? const <BucketInfo>[];
    if (!_hasSearchQuery) {
      return buckets;
    }
    return buckets
        .where((bucket) => bucket.name.toLowerCase().contains(_searchText))
        .toList(growable: false);
  }

  List<ObjectInfo> get _filteredVisibleObjects {
    final visibleObjects = _visibleSelectableObjects;
    if (!_hasSearchQuery) {
      return visibleObjects;
    }
    return visibleObjects
        .where(
          (object) =>
              object.displayName.toLowerCase().contains(_searchText) ||
              object.key.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }

  List<TrashItem> get _filteredTrashItems {
    final items = _trashItems ?? const <TrashItem>[];
    if (!_hasSearchQuery) {
      return items;
    }
    return items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_searchText) ||
              item.originalKey.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }
}
