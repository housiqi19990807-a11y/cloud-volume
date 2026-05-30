// 全局传输状态：共享对象操作任务、轮询 Go 进度快照，并为侧边栏提供聚合速度。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'transfer_queue_storage.dart';

/// 传输任务状态。
enum TransferStatus { pending, running, done, failed, canceled }

enum TransferKind { upload, download, copy, move, delete }

/// 单个传输任务。
class TransferTask {
  TransferTask({
    required this.id,
    required this.kind,
    required this.bucket,
    required this.key,
    required this.localPath,
    this.targetPath = '',
    this.status = TransferStatus.pending,
    this.bytesCompleted = 0,
    this.totalBytes = 0,
    this.speedBytes = 0,
    this.error,
  });

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    return TransferTask(
      id: (json['id'] ?? '').toString(),
      kind: _transferKindFromName((json['kind'] ?? '').toString()),
      bucket: (json['bucket'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      targetPath: (json['targetPath'] ?? '').toString(),
      status: _transferStatusFromName((json['status'] ?? '').toString()),
      bytesCompleted: (json['bytesCompleted'] ?? 0) as int,
      totalBytes: (json['totalBytes'] ?? 0) as int,
      speedBytes: (json['speedBytes'] ?? 0).toDouble(),
      error: json['error']?.toString(),
    );
  }

  final String id;
  final TransferKind kind;
  final String bucket;
  final String key;
  final String localPath;
  String targetPath;
  TransferStatus status;
  int bytesCompleted;
  int totalBytes;
  double speedBytes;
  String? error;

  String get displayName {
    final raw = targetPath.isNotEmpty && (isCopy || isMove) ? targetPath : key;
    final segments = raw.split('/').where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return raw;
    }
    return segments.last;
  }

  String get typeLabel => switch (kind) {
    TransferKind.upload => '上传',
    TransferKind.download => '下载',
    TransferKind.copy => '复制',
    TransferKind.move => '移动',
    TransferKind.delete => '删除',
  };
  bool get isUpload => kind == TransferKind.upload;
  bool get isDownload => kind == TransferKind.download;
  bool get isCopy => kind == TransferKind.copy;
  bool get isMove => kind == TransferKind.move;
  bool get isDelete => kind == TransferKind.delete;
  bool get isRunning => status == TransferStatus.running;
  bool get isPending => status == TransferStatus.pending;
  bool get isCancelable =>
      status == TransferStatus.pending || status == TransferStatus.running;
  bool get isFinished =>
      status == TransferStatus.done ||
      status == TransferStatus.failed ||
      status == TransferStatus.canceled;
  double get progress =>
      totalBytes <= 0 ? 0 : (bytesCompleted / totalBytes).clamp(0, 1);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.name,
      'bucket': bucket,
      'key': key,
      'localPath': localPath,
      'targetPath': targetPath,
      'status': status.name,
      'bytesCompleted': bytesCompleted,
      'totalBytes': totalBytes,
      'speedBytes': speedBytes,
      'error': error,
    };
  }
}

/// 全局队列：页面和侧边栏共享。
class TransferQueue extends ChangeNotifier {
  TransferQueue._();

  static final TransferQueue instance = TransferQueue._();
  static const Duration _activePollInterval = Duration(milliseconds: 700);
  static const Duration _idlePollInterval = Duration(seconds: 2);

  final List<TransferTask> _tasks = [];
  RemoteStorageGateway? _api;
  Timer? _pollTimer;
  Duration? _pollInterval;
  Timer? _persistTimer;
  bool _polling = false;
  int _seed = 0;
  final Set<String> _cancelRequestedIds = <String>{};
  Future<void>? _restoreFuture;

  List<TransferTask> get tasks => List.unmodifiable(_tasks);
  bool get hasRunning => _tasks.any((task) => task.isRunning || task.isPending);
  int get runningCount =>
      _tasks.where((task) => task.isRunning || task.isPending).length;

  void bindApi(RemoteStorageGateway api) {
    _api = api;
    unawaited(restorePersistedTransferQueueState(this).then((_) => pollNow()));
    _ensurePolling();
  }

  TransferTask startTask({
    required TransferKind kind,
    required String bucket,
    required String key,
    required String localPath,
    String targetPath = '',
  }) {
    final task = TransferTask(
      id: 'transfer_${DateTime.now().microsecondsSinceEpoch}_${_seed++}',
      kind: kind,
      bucket: bucket,
      key: key,
      localPath: localPath,
      targetPath: targetPath,
    );
    _tasks.insert(0, task);
    scheduleTransferQueuePersist(this);
    notifyListeners();
    _ensurePolling();
    return task;
  }

  void markTaskFailed(String id, Object error) {
    final task = _taskById(id);
    if (task == null) return;
    if (task.status == TransferStatus.canceled ||
        _cancelRequestedIds.remove(id)) {
      markTaskCanceled(id);
      return;
    }
    task.status = TransferStatus.failed;
    task.error = error.toString();
    task.speedBytes = 0;
    scheduleTransferQueuePersist(this);
    notifyListeners();
    _ensurePolling();
  }

  void markTaskDone(String id) {
    final task = _taskById(id);
    if (task == null) return;
    _cancelRequestedIds.remove(id);
    task.status = TransferStatus.done;
    task.speedBytes = 0;
    task.bytesCompleted = task.totalBytes > 0
        ? task.totalBytes
        : task.bytesCompleted;
    scheduleTransferQueuePersist(this);
    notifyListeners();
    _ensurePolling();
  }

  void markTaskCanceled(String id) {
    final task = _taskById(id);
    if (task == null) return;
    _cancelRequestedIds.remove(id);
    task.status = TransferStatus.canceled;
    task.speedBytes = 0;
    task.error = null;
    scheduleTransferQueuePersist(this);
    notifyListeners();
    _ensurePolling();
  }

  bool canCancelTask(String id) => _canCancelTask(_taskById(id));

  int cancelableTaskCount(Iterable<String> ids) =>
      _countTasks(ids, _canCancelTask);

  bool canTriggerTask(String id) => _canTriggerTask(_taskById(id));

  int triggerableTaskCount(Iterable<String> ids) =>
      _countTasks(ids, _canTriggerTask);

  Future<void> cancelTask(String id) async {
    final existingTask = _taskById(id);
    if (!_canCancelTask(existingTask)) return;
    final task = existingTask!;
    _cancelRequestedIds.add(id);
    task.status = TransferStatus.canceled;
    task.speedBytes = 0;
    task.error = null;
    scheduleTransferQueuePersist(this);
    notifyListeners();
    if (_api != null) {
      await _api!.cancelTransfer(id);
    }
    _ensurePolling();
  }

  Future<int> cancelTasks(Iterable<String> ids) async {
    final cancellations = <Future<void>>[];
    var canceled = 0;
    for (final id in ids.toSet()) {
      final task = _taskById(id);
      if (!_canCancelTask(task)) {
        continue;
      }
      cancellations.add(cancelTask(id));
      canceled++;
    }
    await Future.wait(cancellations);
    return canceled;
  }

  Future<bool> triggerTaskNow(String id) async {
    final existingTask = _taskById(id);
    if (!_canTriggerTask(existingTask)) {
      return false;
    }
    final triggered = await _api!.triggerTransfer(id);
    await pollNow();
    return triggered;
  }

  Future<int> triggerTasksNow(Iterable<String> ids) async {
    if (_api == null) {
      return 0;
    }
    var triggeredCount = 0;
    for (final id in ids.toSet()) {
      final task = _taskById(id);
      if (!_canTriggerTask(task)) {
        continue;
      }
      final triggered = await _api!.triggerTransfer(id);
      if (triggered) {
        triggeredCount++;
      }
    }
    await pollNow();
    return triggeredCount;
  }

  bool isCancelRequested(String id) => _cancelRequestedIds.contains(id);

  TransferStatus? statusOf(String id) => _taskById(id)?.status;

  TransferTask? findActiveTask({
    required TransferKind kind,
    required String bucket,
    required String key,
    required String localPath,
    String targetPath = '',
  }) {
    for (final task in _tasks) {
      if (task.kind != kind) continue;
      if (task.bucket != bucket || task.key != key) continue;
      if (task.localPath != localPath) continue;
      if (task.targetPath != targetPath) continue;
      if (!task.isFinished) {
        return task;
      }
    }
    return null;
  }

  void refreshFromSnapshots(List<TransferSnapshot> snapshots) {
    var changed = false;
    var shouldPersist = false;
    for (final snapshot in snapshots) {
      final task =
          _taskById(snapshot.id) ??
          (() {
            changed = true;
            shouldPersist = true;
            return _addRemoteTask(snapshot);
          })();
      final nextStatus = _statusFromWire(snapshot.status);
      final resolvedStatus =
          _cancelRequestedIds.contains(snapshot.id) &&
              nextStatus != TransferStatus.canceled &&
              nextStatus != TransferStatus.done &&
              nextStatus != TransferStatus.failed
          ? TransferStatus.canceled
          : nextStatus;
      if (task.status != resolvedStatus) {
        changed = true;
        shouldPersist = true;
      }
      if (_cancelRequestedIds.contains(snapshot.id) &&
          nextStatus != TransferStatus.canceled &&
          nextStatus != TransferStatus.done &&
          nextStatus != TransferStatus.failed) {
        task.status = TransferStatus.canceled;
      } else {
        if (nextStatus == TransferStatus.canceled ||
            nextStatus == TransferStatus.done ||
            nextStatus == TransferStatus.failed) {
          _cancelRequestedIds.remove(snapshot.id);
        }
        task.status = nextStatus;
      }
      if (task.bytesCompleted != snapshot.bytesCompleted ||
          task.totalBytes != snapshot.totalBytes ||
          task.speedBytes != snapshot.speedBytes ||
          task.targetPath != snapshot.targetPath ||
          task.error != snapshot.error) {
        changed = true;
      }
      if (task.totalBytes != snapshot.totalBytes ||
          task.targetPath != snapshot.targetPath ||
          task.error != snapshot.error) {
        shouldPersist = true;
      }
      task.bytesCompleted = snapshot.bytesCompleted;
      task.totalBytes = snapshot.totalBytes;
      task.speedBytes = snapshot.speedBytes;
      task.targetPath = snapshot.targetPath;
      task.error = snapshot.error;
    }
    if (changed) {
      if (shouldPersist) {
        scheduleTransferQueuePersist(this);
      }
      notifyListeners();
    }
    _ensurePolling();
  }

  String get uploadSpeedText => _speedTextFor(true);
  String get downloadSpeedText => _speedTextFor(false);
  String get objectOperationSpeedText => _speedTextForObjectOps();

  String get speedSummary {
    final up = uploadSpeedText;
    final down = downloadSpeedText;
    final ops = objectOperationSpeedText;
    if (up.isEmpty && down.isEmpty && ops.isEmpty) {
      return hasRunning ? '$runningCount 个任务进行中' : '暂无任务';
    }
    final parts = <String>[
      if (up.isNotEmpty) up,
      if (down.isNotEmpty) down,
      if (ops.isNotEmpty) ops,
    ];
    return parts.join('  ');
  }

  @visibleForTesting
  void resetForTest() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInterval = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    _polling = false;
    _seed = 0;
    _api = null;
    _restoreFuture = null;
    _tasks.clear();
    _cancelRequestedIds.clear();
    notifyListeners();
  }

  @visibleForTesting
  Future<void> restorePersistedStateForTest() =>
      restorePersistedTransferQueueState(this);

  @visibleForTesting
  Future<void> flushPersistenceForTest() => persistTransferQueueState(this);

  Future<void> pollNow() async {
    if (_api == null || _polling) return;
    _polling = true;
    try {
      final snapshots = await _api!.listTransferJobs();
      refreshFromSnapshots(snapshots);
    } finally {
      _polling = false;
    }
  }

  void _ensurePolling() {
    if (_api == null) return;
    final nextInterval = hasRunning ? _activePollInterval : _idlePollInterval;
    if (_pollTimer != null && _pollInterval == nextInterval) {
      return;
    }
    _pollTimer?.cancel();
    _pollInterval = nextInterval;
    _pollTimer = Timer.periodic(nextInterval, (_) => unawaited(pollNow()));
  }

  TransferTask? _taskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  bool _canCancelTask(TransferTask? task) => task?.isCancelable ?? false;

  bool _canTriggerTask(TransferTask? task) =>
      _api != null &&
      task != null &&
      task.status == TransferStatus.pending &&
      task.isUpload;

  int _countTasks(
    Iterable<String> ids,
    bool Function(TransferTask? task) predicate,
  ) {
    var count = 0;
    for (final id in ids.toSet()) {
      if (predicate(_taskById(id))) {
        count++;
      }
    }
    return count;
  }

  TransferTask _addRemoteTask(TransferSnapshot snapshot) {
    final task = TransferTask(
      id: snapshot.id,
      kind: _kindFromWire(snapshot.type),
      bucket: snapshot.bucket,
      key: snapshot.key,
      localPath: snapshot.localPath,
      targetPath: snapshot.targetPath,
    );
    _tasks.insert(0, task);
    return task;
  }

  Future<void> _restorePersistedTasks() async {
    await loadPersistedTransferQueueStateData(this);
    if (_tasks.isNotEmpty) {
      scheduleTransferQueuePersist(this);
      notifyListeners();
    }
  }

  TransferKind _kindFromWire(String value) {
    switch (value) {
      case 'download':
        return TransferKind.download;
      case 'copy':
        return TransferKind.copy;
      case 'move':
        return TransferKind.move;
      case 'delete':
        return TransferKind.delete;
      default:
        return TransferKind.upload;
    }
  }

  TransferStatus _statusFromWire(String value) {
    switch (value) {
      case 'running':
        return TransferStatus.running;
      case 'done':
        return TransferStatus.done;
      case 'failed':
        return TransferStatus.failed;
      case 'canceled':
        return TransferStatus.canceled;
      default:
        return TransferStatus.pending;
    }
  }

  String _speedTextFor(bool isUpload) {
    final total = _tasks
        .where((task) => task.isUpload == isUpload && task.isRunning)
        .fold<double>(0, (sum, task) => sum + task.speedBytes);
    if (total <= 0) return '';
    final prefix = isUpload ? '↑' : '↓';
    return '$prefix ${formatBytesPerSecond(total)}';
  }

  String _speedTextForObjectOps() {
    final total = _tasks
        .where((task) => (task.isCopy || task.isMove) && task.isRunning)
        .fold<double>(0, (sum, task) => sum + task.speedBytes);
    if (total <= 0) return '';
    return '↔ ${formatBytesPerSecond(total)}';
  }
}

TransferKind _transferKindFromName(String value) {
  return switch (value) {
    'download' => TransferKind.download,
    'copy' => TransferKind.copy,
    'move' => TransferKind.move,
    'delete' => TransferKind.delete,
    _ => TransferKind.upload,
  };
}

TransferStatus _transferStatusFromName(String value) {
  return switch (value) {
    'running' => TransferStatus.running,
    'done' => TransferStatus.done,
    'failed' => TransferStatus.failed,
    'canceled' => TransferStatus.canceled,
    _ => TransferStatus.pending,
  };
}
