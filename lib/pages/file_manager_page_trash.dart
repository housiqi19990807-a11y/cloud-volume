// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页回收站逻辑：按 bucket 浏览、恢复和彻底删除软删除对象。

extension _FileManagerPageTrash on _FileManagerPageState {
  Future<bool> _openBucketTrash([String? bucket]) async {
    final targetBucket = bucket ?? _activeBucket;
    if (targetBucket == null) {
      return false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listTrash(widget.config, targetBucket);
      if (!mounted) return false;
      setState(() {
        _activeBucket = targetBucket;
        _objects = null;
        _trashItems = items;
        _prefix = '';
        _breadcrumbs = const <String>[];
        _showTrash = true;
        _selectedObjectKeys.clear();
        _loading = false;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      return false;
    }
  }

  Future<void> _closeBucketTrash() async {
    if (_isTrashHome) {
      await _loadBuckets();
      return;
    }
    if (_activeBucket == null) {
      return;
    }
    await _loadObjects(_activeBucket!, '');
  }

  Future<void> _restoreTrashItem(TrashItem item) async {
    if (_activeBucket == null) {
      return;
    }
    try {
      await widget.api.restoreTrashItem(widget.config, _activeBucket!, item.id);
      if (!mounted) return;
      await _openBucketTrash(_activeBucket!);
    } catch (error) {
      _showPageError(error);
    }
  }

  Future<void> _deleteTrashItemPermanently(TrashItem item) async {
    if (_activeBucket == null) {
      return;
    }
    final confirmed = await showDeleteTrashItemDialog(context, item);
    if (!confirmed) {
      return;
    }
    try {
      await widget.api.deleteTrashItem(widget.config, _activeBucket!, item.id);
      if (!mounted) return;
      await _openBucketTrash(_activeBucket!);
    } catch (error) {
      _showPageError(error);
    }
  }

  Widget _buildTrashView(ShadThemeData theme) {
    final items = _trashItems ?? const <TrashItem>[];
    if (items.isEmpty) {
      return _empty(theme, LucideIcons.trash2, '此存储桶回收站为空');
    }
    return FileManagerTrashBrowser(
      items: items,
      isGrid: _isGrid,
      onRestore: (item) => unawaited(_restoreTrashItem(item)),
      onDeletePermanently: (item) =>
          unawaited(_deleteTrashItemPermanently(item)),
    );
  }
}
