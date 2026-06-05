// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页操作逻辑：上传、目录创建、对象打开/下载以及右键动作。

extension _FileManagerPageActions on _FileManagerPageState {
  Future<void> _upload() async {
    if (_activeBucket == null) return;
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: widget.api.capabilities.supportsBrowserTransfers,
    );
    if (result == null || result.files.isEmpty) return;
    final bucket = _activeBucket!;
    for (final file in result.files) {
      final key = _prefix + file.name;
      final path = file.path;
      final bytes = file.bytes;
      if (path == null && bytes == null) {
        continue;
      }
      final task = TransferQueue.instance.startTask(
        kind: TransferKind.upload,
        bucket: bucket,
        key: key,
        localPath: path ?? file.name,
      );
      if (bytes != null) {
        unawaited(_runBrowserUploadTask(task, bucket, bytes, file.name));
      } else {
        unawaited(_runUploadTask(task, bucket));
      }
    }
  }

  Future<void> _createDirectory() async {
    if (_activeBucket == null) return;
    final controller = TextEditingController();
    String? errorText;
    bool creating = false;

    await showShadDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return CreateDirectoryDialog(
              controller: controller,
              errorText: errorText,
              creating: creating,
              onCancel: () => Navigator.of(dialogContext).pop(),
              onCreate: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = '目录名称不能为空');
                  return;
                }
                setDialogState(() {
                  creating = true;
                  errorText = null;
                });
                try {
                  await widget.api.createDirectory(
                    widget.config,
                    _activeBucket!,
                    _prefix,
                    name,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _loadObjects(_activeBucket!, _prefix);
                } catch (error) {
                  setDialogState(() {
                    creating = false;
                    errorText = error.toString();
                  });
                }
              },
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _runUploadTask(TransferTask task, String bucket) async {
    try {
      await widget.api.uploadFile(
        widget.config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
      if (!mounted || _activeBucket != bucket) return;
      await _loadObjects(bucket, _prefix);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
    }
  }

  Future<void> _runBrowserUploadTask(
    TransferTask task,
    String bucket,
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      await widget.api.uploadBytes(
        widget.config,
        task.bucket,
        task.key,
        bytes,
        task.id,
        fileName: fileName,
      );
      TransferQueue.instance.markTaskDone(task.id);
      if (!mounted || _activeBucket != bucket) return;
      await _loadObjects(bucket, _prefix);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
    }
  }

  Future<void> _openObject(ObjectInfo object) async {
    if (_activeBucket == null) return;
    await _showObjectPreview(object);
  }

  Future<void> _showObjectPreview(ObjectInfo object) async {
    final bucket = _activeBucket;
    if (bucket == null) return;
    final kind = previewKindForName(object.displayName);
    var loading = kind == FilePreviewKind.image;
    FilePreviewSource? source;
    String? errorText;

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
                      config: widget.config,
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
              errorText: errorText,
              onSaveAs: () => unawaited(_downloadObject(object)),
              onDownload: () =>
                  unawaited(_downloadObjectToDefaultDirectory(object)),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadObjectToDefaultDirectory(ObjectInfo object) async {
    if (_activeBucket == null) return;
    try {
      await FileAccessService.instance.downloadObjectToDefaultDirectory(
        api: widget.api,
        config: widget.config,
        bucket: _activeBucket!,
        object: object,
      );
    } catch (error) {
      _showPageError(error);
    }
  }

  Future<void> _downloadObject(ObjectInfo object) async {
    if (_activeBucket == null) return;
    try {
      await FileAccessService.instance.downloadObjectWithPicker(
        api: widget.api,
        config: widget.config,
        bucket: _activeBucket!,
        object: object,
      );
    } catch (error) {
      _showPageError(error);
    }
  }

  Future<void> _handleObjectAction(
    ObjectInfo object,
    FileObjectAction action,
  ) async {
    if (!mounted || _activeBucket == null) return;
    try {
      if (action == FileObjectAction.open) {
        await _openObject(object);
        return;
      }
      if (action == FileObjectAction.download) {
        await _downloadObject(object);
        return;
      }
      if (action == FileObjectAction.share) {
        final durationSec = await showShareDurationDialog(
          context,
          title: '创建分享',
          description: '为当前文件生成一个可复制的分享链接。',
          confirmLabel: '创建分享',
        );
        if (durationSec == null) {
          return;
        }
        final shareRecord = await widget.api.createShare(
          widget.config,
          _activeBucket!,
          object.key,
          object.displayName,
          durationSec,
        );
        ShareRecordsNotifier.instance.markChanged();
        if (!mounted) {
          return;
        }
        await showShareLinkDialog(context, record: shareRecord);
        return;
      }
      if (action == FileObjectAction.copy || action == FileObjectAction.move) {
        final targetPath = await showObjectTargetPathDialog(
          context,
          object,
          move: action == FileObjectAction.move,
        );
        if (targetPath == null ||
            targetPath.isEmpty ||
            targetPath == object.key) {
          return;
        }
        final task = TransferQueue.instance.startTask(
          kind: action == FileObjectAction.move
              ? TransferKind.move
              : TransferKind.copy,
          bucket: _activeBucket!,
          key: object.key,
          localPath: '',
          targetPath: targetPath,
        );
        try {
          if (action == FileObjectAction.move) {
            await widget.api.moveObject(
              widget.config,
              _activeBucket!,
              object.key,
              targetPath,
              object.isDir,
              task.id,
            );
            await FileAccessService.instance.evictCacheForObject(
              config: widget.config,
              bucket: _activeBucket!,
              object: object,
            );
          } else {
            await widget.api.copyObject(
              widget.config,
              _activeBucket!,
              object.key,
              targetPath,
              object.isDir,
              task.id,
            );
          }
          TransferQueue.instance.markTaskDone(task.id);
        } catch (error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          rethrow;
        }
      }
      if (!mounted) return;
      if (action == FileObjectAction.rename) {
        final newName = await showRenameObjectDialog(context, object);
        if (newName == null ||
            newName.isEmpty ||
            newName == object.displayName) {
          return;
        }
        await widget.api.renameObject(
          widget.config,
          _activeBucket!,
          object.key,
          object.isDir,
          newName,
        );
        await FileAccessService.instance.evictCacheForObject(
          config: widget.config,
          bucket: _activeBucket!,
          object: object,
        );
      } else if (action == FileObjectAction.delete) {
        if (!mounted) return;
        final confirmed = await showDeleteObjectDialog(context, object);
        if (!confirmed) return;
        _queueObjectDeletes(<ObjectInfo>[object]);
        return;
      }
      if (!mounted) return;
      await _loadObjects(_activeBucket!, _prefix);
    } catch (error) {
      _showPageError(error);
    }
  }

  void _showPageSnack(String message) {
    if (!mounted) {
      return;
    }
    showAppToast(context, message: message);
  }

  void _showPageError(Object error) {
    if (!mounted) {
      return;
    }
    _showPageMessage(title: '操作失败', message: describeBridgeError(error));
  }

  void _showPageMessage({required String title, required String message}) {
    if (!mounted) {
      return;
    }
    unawaited(
      showShadDialog<void>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: Text(title),
          description: Text(message),
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 12),
                ShadButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showWebDavEntry(String bucket) {
    final uri = widget.api.webDavUri(bucket);
    if (uri == null) {
      _showPageMessage(title: 'WebDAV 不可用', message: '当前客户端未提供 WebDAV 地址。');
      return;
    }
    _showPageMessage(
      title: 'WebDAV 地址',
      message: '请使用初始化或系统设置中配置的 WebDAV 账号密码访问：\n$uri',
    );
  }

  void _queueObjectDeletes(List<ObjectInfo> objects) {
    if (_activeBucket == null || objects.isEmpty) {
      return;
    }
    final bucket = _activeBucket!;
    final targets = objects
        .where((object) => !_deletingObjectKeys.contains(object.key))
        .toList();
    if (targets.isEmpty) {
      return;
    }
    setState(() {
      for (final object in targets) {
        _deletingObjectKeys.add(object.key);
        _selectedObjectKeys.remove(object.key);
      }
    });

    final futures = targets
        .map((object) => _runDeleteTask(bucket, object))
        .toList(growable: false);
    unawaited(() async {
      final errors = await Future.wait(futures);
      if (!mounted || _activeBucket != bucket) {
        return;
      }
      await _loadObjects(bucket, _prefix);
      final failures = errors.whereType<Object>().toList(growable: false);
      if (failures.isNotEmpty) {
        _showPageMessage(
          title: '删除失败',
          message: failures.length == 1
              ? failures.first.toString()
              : '有 ${failures.length} 个删除任务失败，请在任务队列中查看详情。',
        );
      }
    }());
  }

  Future<Object?> _runDeleteTask(String bucket, ObjectInfo object) async {
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.delete,
      bucket: bucket,
      key: object.key,
      localPath: '',
    );
    try {
      await widget.api.deleteObject(
        widget.config,
        bucket,
        object.key,
        object.isDir,
        task.id,
      );
      await FileAccessService.instance.evictCacheForObject(
        config: widget.config,
        bucket: bucket,
        object: object,
      );
      TransferQueue.instance.markTaskDone(task.id);
      return null;
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      if (mounted) {
        setState(() => _deletingObjectKeys.remove(object.key));
      }
      return error;
    }
  }
}
