// ignore_for_file: invalid_use_of_protected_member

// 文件管理页对象删除队列：让行级删除以任务形式异步执行并刷新列表。

part of 'file_manager_page.dart';

extension _FileManagerPageObjectDeletes on _FileManagerPageState {
  void _queueObjectDeletes(List<ObjectInfo> objects) {
    if (_activeBucket == null ||
        _activeBucketEntry == null ||
        objects.isEmpty) {
      return;
    }
    final bucketEntry = _activeBucketEntry!;
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
        .map((object) => _runDeleteTask(bucketEntry, object))
        .toList(growable: false);
    unawaited(() async {
      final errors = await Future.wait(futures);
      if (!mounted || _activeBucketId != bucketEntry.id) {
        return;
      }
      await _loadObjects(bucketEntry, _prefix);
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

  Future<Object?> _runDeleteTask(
    FileManagerBucketEntry bucket,
    ObjectInfo object,
  ) async {
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.delete,
      bucket: bucket.bucket.name,
      key: object.key,
      localPath: '',
    );
    try {
      await widget.api.deleteObject(
        bucket.config,
        bucket.bucket.name,
        object.key,
        object.isDir,
        task.id,
      );
      await FileAccessService.instance.evictCacheForObject(
        config: bucket.config,
        bucket: bucket.bucket.name,
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
