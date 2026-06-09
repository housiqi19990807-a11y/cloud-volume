// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页多选逻辑：维护选中集合，并处理批量下载与批量删除。

extension _FileManagerPageSelection on _FileManagerPageState {
  List<ObjectInfo> get _visibleSelectableObjects {
    return filterVisibleObjects(
      _objects ?? const <ObjectInfo>[],
      hideDotFiles: _activeConfig.hideDotFiles,
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

  void _replaceSelectedObjects(Set<String> keys) {
    final visibleKeys = _filteredVisibleObjects
        .map((object) => object.key)
        .toSet();
    final normalized = keys.where(visibleKeys.contains).toSet();
    if (_selectedObjectKeys.length == normalized.length &&
        _selectedObjectKeys.containsAll(normalized)) {
      return;
    }
    setState(() {
      _selectedObjectKeys
        ..clear()
        ..addAll(normalized);
    });
  }

  void _selectObjectsForContextMenu(ObjectInfo object) {
    if (_selectedObjectKeys.contains(object.key)) {
      return;
    }
    setState(() {
      _selectedObjectKeys
        ..clear()
        ..add(object.key);
    });
  }

  void _clearSelection() {
    if (_selectedObjectKeys.isEmpty) {
      return;
    }
    setState(_selectedObjectKeys.clear);
  }

  void _toggleSelectAllObjects() {
    final selectableKeys = _filteredVisibleObjects
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
    if (widget.api.capabilities.supportsBrowserTransfers) {
      try {
        for (final object in files) {
          unawaited(
            FileAccessService.instance.downloadObjectToPath(
              api: widget.api,
              config: _activeConfig,
              bucket: _activeBucket!,
              object: object,
              savePath: object.displayName,
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
      return;
    }
    final targetDirectory = await resolveDefaultDownloadDirectory(
      _activeConfig.defaultDownloadDirectory,
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
            config: _activeConfig,
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
    if (!_currentBucketWritable) {
      _ensureCurrentDirectoryWritable();
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
