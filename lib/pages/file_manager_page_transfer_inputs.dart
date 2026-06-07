// 文件管理页文件输入：处理拖拽上传、剪贴板上传，以及复制远端文件到系统剪贴板。

part of 'file_manager_page.dart';

extension _FileManagerPageTransferInputs on _FileManagerPageState {
  Future<void> _uploadLocalPaths(List<String> localPaths) async {
    if (!_acceptsFileTransferInput || localPaths.isEmpty) {
      return;
    }
    final tasks = <TransferTask>[];
    for (final localPath in localPaths) {
      final task = _queueLocalUpload(localPath);
      if (task != null) {
        tasks.add(task);
      }
    }
    await _showUploadProgressDialogForTasks(tasks);
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
          config: widget.config,
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
