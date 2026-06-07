part of 'file_manager_page.dart';

// 文件管理页上传反馈：统一弹出上传进度拟态框，允许关闭后继续后台运行。

extension _FileManagerPageUploadFeedback on _FileManagerPageState {
  Future<void> _showUploadProgressDialogForTasks(
    List<TransferTask> tasks,
  ) async {
    if (!mounted || tasks.isEmpty) {
      return;
    }
    final taskIds = tasks.map((task) => task.id).toList(growable: false);
    await showShadDialog<void>(
      context: context,
      builder: (dialogContext) => UploadProgressDialog(
        taskIds: taskIds,
        currentPathLabel: _uploadTargetLabel,
        onRunInBackground: () {
          Navigator.of(dialogContext).pop();
          _showPageSnack('上传已转为后台进行');
        },
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  String get _uploadTargetLabel {
    final bucket = _activeBucket;
    if (bucket == null) {
      return '';
    }
    if (_prefix.isEmpty) {
      return bucket;
    }
    return '$bucket / $_prefix';
  }
}
