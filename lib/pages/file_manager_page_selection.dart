// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页多选逻辑：维护选中集合，并处理批量下载与批量删除。

extension _FileManagerPageSelection on _FileManagerPageState {
  List<ObjectInfo> get _visibleSelectableObjects {
    return filterVisibleObjects(
      _objects ?? const <ObjectInfo>[],
      hideDotFiles: widget.config.hideDotFiles,
    );
  }

  List<ObjectInfo> get _selectedObjects {
    return (_objects ?? const <ObjectInfo>[])
        .where((object) => _selectedObjectKeys.contains(object.key))
        .toList();
  }

  void _toggleObjectSelection(ObjectInfo object) {
    setState(() {
      if (!_selectedObjectKeys.add(object.key)) {
        _selectedObjectKeys.remove(object.key);
      }
    });
  }

  void _clearSelection() {
    if (_selectedObjectKeys.isEmpty) {
      return;
    }
    setState(_selectedObjectKeys.clear);
  }

  void _toggleSelectAllObjects() {
    final selectableKeys = _visibleSelectableObjects
        .map((object) => object.key)
        .toSet();
    if (selectableKeys.isEmpty) {
      return;
    }

    final hasUnselected = selectableKeys.any(
      (key) => !_selectedObjectKeys.contains(key),
    );

    setState(() {
      if (hasUnselected) {
        _selectedObjectKeys.addAll(selectableKeys);
      } else {
        _selectedObjectKeys.removeAll(selectableKeys);
      }
    });
  }

  Future<void> _downloadSelectedObjects() async {
    if (_activeBucket == null) {
      return;
    }
    final files = _selectedObjects.where((object) => !object.isDir).toList();
    if (files.isEmpty) {
      return;
    }
    final targetDirectory = await resolveDefaultDownloadDirectory(
      widget.config.defaultDownloadDirectory,
    );
    if (targetDirectory == null || targetDirectory.isEmpty) {
      if (!mounted) {
        return;
      }
      _showPageMessage(title: '下载失败', message: '无法确定默认下载目录');
      return;
    }

    try {
      for (final object in files) {
        unawaited(
          FileAccessService.instance.downloadObjectToPath(
            api: widget.api,
            config: widget.config,
            bucket: _activeBucket!,
            object: object,
            savePath: path.join(targetDirectory, object.displayName),
          ),
        );
      }
      _clearSelection();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showPageError(error);
    }
  }

  Future<void> _deleteSelectedObjects() async {
    if (!mounted || _activeBucket == null || _selectedObjectKeys.isEmpty) {
      return;
    }
    final selected = _selectedObjects;
    final confirmed = await showDeleteObjectsDialog(context, selected.length);
    if (!confirmed) {
      return;
    }
    _queueObjectDeletes(selected);
  }
}
