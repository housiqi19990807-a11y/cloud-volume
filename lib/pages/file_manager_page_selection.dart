// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页多选逻辑：维护选中集合，并处理批量下载与批量删除。

extension _FileManagerPageSelection on _FileManagerPageState {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法确定默认下载目录')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
    try {
      for (final object in selected) {
        await widget.api.deleteObject(
          widget.config,
          _activeBucket!,
          object.key,
          object.isDir,
        );
        await FileAccessService.instance.evictCacheForObject(
          bucket: _activeBucket!,
          object: object,
        );
      }
      _clearSelection();
      await _loadObjects(_activeBucket!, _prefix);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
