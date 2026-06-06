// 文件管理页文件输入：处理拖拽上传、剪贴板上传，以及复制远端文件到系统剪贴板。

part of 'file_manager_page.dart';

extension _FileManagerPageTransferInputs on _FileManagerPageState {
  Future<void> _uploadLocalPaths(List<String> localPaths) async {
    if (!_acceptsFileTransferInput || localPaths.isEmpty) {
      return;
    }
    var queued = 0;
    for (final localPath in localPaths) {
      _queueLocalUpload(localPath);
      queued += 1;
    }
    if (queued > 0) {
      _showPageSnack('已加入 $queued 个上传任务');
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
