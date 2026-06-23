part of 'file_manager_page.dart';

// 文件预览页逻辑：维护弹窗内预览、下载进度和外部应用打开流程。

extension _FileManagerPagePreview on _FileManagerPageState {
  Future<void> _openObject(ObjectInfo object) async {
    if (_activeBucket == null) return;
    await _showObjectPreview(object);
  }

  Future<void> _showObjectPreview(ObjectInfo object) async {
    final bucket = _activeBucket;
    if (bucket == null) return;
    final kind = previewKindForName(object.displayName);
    if (!mounted) return;
    var loading = kind == FilePreviewKind.image;
    FilePreviewTransferState? transfer;
    FilePreviewSource? source;
    String? errorText;
    // 远端对象不存在时置为 true：用于隐藏下载相关动作并在关闭弹窗后刷新目录元数据。
    var unavailable = false;

    await showShadDialog(
      context: context,
      builder: (dialogContext) {
        var started = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (loading && !started) {
              started = true;
              unawaited(
                FileAccessService.instance
                    .preparePreviewSource(
                      api: widget.api,
                      config: _activeConfig,
                      bucket: bucket,
                      object: object,
                    )
                    .then((value) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        source = value;
                        loading = false;
                      });
                    })
                    .catchError((error) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        errorText = describeBridgeError(error);
                        unavailable = isObjectMissingError(error);
                        loading = false;
                      });
                    }),
              );
            }
            return FilePreviewDialog(
              object: object,
              kind: kind,
              source: source,
              loading: loading,
              transfer: transfer,
              errorText: errorText,
              unavailable: unavailable,
              onOpenWithSystem: () {
                if (transfer != null) return;
                transfer = _runningTransferState(_PreviewTransferAction.open);
                setDialogState(() {});
                unawaited(
                  _runPreviewTransfer(
                    action: _PreviewTransferAction.open,
                    object: object,
                    dialogContext: dialogContext,
                    setDialogState: setDialogState,
                    setTransfer: (value) => transfer = value,
                  ),
                );
              },
              onSaveAs: () {
                if (transfer != null) return;
                unawaited(
                  _runPreviewTransfer(
                    action: _PreviewTransferAction.saveAs,
                    object: object,
                    dialogContext: dialogContext,
                    setDialogState: setDialogState,
                    setTransfer: (value) => transfer = value,
                    onMissingDetected: () {
                      unavailable = true;
                    },
                  ),
                );
              },
              onDownload: () {
                if (transfer != null) return;
                transfer = _runningTransferState(
                  _PreviewTransferAction.download,
                );
                setDialogState(() {});
                unawaited(
                  _runPreviewTransfer(
                    action: _PreviewTransferAction.download,
                    object: object,
                    dialogContext: dialogContext,
                    setDialogState: setDialogState,
                    setTransfer: (value) => transfer = value,
                    onMissingDetected: () {
                      unavailable = true;
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
    // 关闭弹窗后，如果是因为对象在远端已不存在，触发一次目录元数据刷新，
    // 让已删除的条目从列表中消失。
    if (unavailable && _activeBucketEntry != null && mounted) {
      await _reloadObjectsAfterBucketMutation(_activeBucketEntry!, _prefix);
    }
  }

  Future<void> _runPreviewTransfer({
    required _PreviewTransferAction action,
    required ObjectInfo object,
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required ValueChanged<FilePreviewTransferState?> setTransfer,
    VoidCallback? onMissingDetected,
  }) async {
    final bucket = _activeBucket;
    if (bucket == null) return;
    try {
      final request = switch (action) {
        _PreviewTransferAction.open =>
          await FileAccessService.instance.prepareObjectForExternalOpen(
            api: widget.api,
            config: _activeConfig,
            bucket: bucket,
            object: object,
          ),
        _PreviewTransferAction.saveAs =>
          await FileAccessService.instance.prepareDownloadObjectWithPicker(
            api: widget.api,
            config: _activeConfig,
            bucket: bucket,
            object: object,
          ),
        _PreviewTransferAction.download =>
          await FileAccessService.instance
              .prepareDownloadObjectToDefaultDirectory(
                api: widget.api,
                config: _activeConfig,
                bucket: bucket,
                object: object,
              ),
      };
      if (request == null) {
        if (!dialogContext.mounted) return;
        setDialogState(() => setTransfer(null));
        return;
      }
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setTransfer(_runningTransferState(action, task: request.task));
      });
      final localPath = await request.completion;
      if (action == _PreviewTransferAction.open) {
        await FileAccessService.instance.openLocalPath(localPath);
        if (!dialogContext.mounted) return;
        Navigator.of(dialogContext).pop();
        return;
      }
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setTransfer(_doneTransferState(action, task: request.task));
      });
    } catch (error) {
      if (!dialogContext.mounted) {
        _showPageError(error);
        return;
      }
      final missing = isObjectMissingError(error);
      if (missing) {
        onMissingDetected?.call();
      }
      setDialogState(() {
        setTransfer(
          _runningTransferState(action, errorText: describeBridgeError(error)),
        );
      });
    }
  }

  FilePreviewTransferState _runningTransferState(
    _PreviewTransferAction action, {
    TransferTask? task,
    String? errorText,
  }) {
    return FilePreviewTransferState(
      runningTitle: action.runningTitle,
      waitingText: action.waitingText,
      doneTitle: action.doneTitle,
      doneText: action.doneText,
      task: task,
      errorText: errorText,
    );
  }

  FilePreviewTransferState _doneTransferState(
    _PreviewTransferAction action, {
    TransferTask? task,
  }) {
    return FilePreviewTransferState(
      runningTitle: action.runningTitle,
      waitingText: action.waitingText,
      doneTitle: action.doneTitle,
      doneText: action.doneText,
      task: task,
      done: true,
    );
  }
}

enum _PreviewTransferAction {
  open(
    runningTitle: '正在下载并准备打开',
    waitingText: '下载完成后会自动使用外部应用打开。',
    doneTitle: '已打开',
    doneText: '文件已交给系统应用打开。',
  ),
  saveAs(
    runningTitle: '正在另存为',
    waitingText: '文件正在保存到你选择的位置。',
    doneTitle: '另存为完成',
    doneText: '文件已保存到本地。',
  ),
  download(
    runningTitle: '正在下载',
    waitingText: '文件正在保存到默认下载目录。',
    doneTitle: '下载完成',
    doneText: '文件已保存到默认下载目录。',
  );

  const _PreviewTransferAction({
    required this.runningTitle,
    required this.waitingText,
    required this.doneTitle,
    required this.doneText,
  });

  final String runningTitle;
  final String waitingText;
  final String doneTitle;
  final String doneText;
}
