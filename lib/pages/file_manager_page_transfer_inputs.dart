// 文件管理页文件输入：处理拖拽上传、剪贴板上传，以及复制远端文件到系统剪贴板。

part of 'file_manager_page.dart';

extension _FileManagerPageTransferInputs on _FileManagerPageState {
  Future<void> _uploadLocalPaths(List<String> localPaths) async {
    if (!_acceptsFileTransferInput || localPaths.isEmpty) {
      return;
    }
    if (!_ensureCurrentDirectoryWritable()) return;
    final bucket = _activeBucketEntry;
    if (bucket == null) {
      return;
    }
    final entries = await DesktopFileTransferService.instance
        .localUploadEntries(localPaths);
    final tasks = <TransferTask>[];
    var createdDirectoryCount = 0;
    for (final entry in entries.where((entry) => entry.isDirectory)) {
      try {
        await widget.api.createDirectory(
          bucket.config,
          bucket.bucket.name,
          _prefix,
          entry.relativeKey,
        );
        createdDirectoryCount++;
      } catch (error) {
        _showPageError(error);
        return;
      }
    }
    for (final entry in entries.where((entry) => !entry.isDirectory)) {
      final task = _queueLocalUpload(
        entry.localPath,
        relativeKey: entry.relativeKey,
      );
      if (task != null) {
        tasks.add(task);
      }
    }
    await _showUploadProgressDialogForTasks(tasks);
    if (tasks.isEmpty && createdDirectoryCount > 0) {
      await _loadObjects(bucket, _prefix);
      _showPageSnack('已创建 $createdDirectoryCount 个目录');
    }
  }

  Future<void> _copySelectedObjectsToClipboard() async {
    if (_activeBucket == null) {
      return;
    }
    final files = _selectedObjects.where((object) => !object.isDir).toList();
    if (files.isEmpty) {
      return;
    }
    try {
      final localPaths = <String>[];
      for (final object in files) {
        final localPath = await FileAccessService.instance.prepareLocalCopyPath(
          api: widget.api,
          config: _activeConfig,
          bucket: _activeBucket!,
          object: object,
        );
        localPaths.add(localPath);
      }
      await DesktopFileTransferService.instance.writeLocalFilesToClipboard(
        localPaths,
      );
      _showPageSnack('已复制 ${localPaths.length} 个文件，可粘贴到本地目录');
    } catch (error) {
      _showPageError(error);
    }
  }
}
