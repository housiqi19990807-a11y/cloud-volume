// 全局传输状态：共享上传/下载任务、轮询 Go 进度快照，并为侧边栏提供聚合速度。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/services/remote_storage_api.dart';

/// 传输任务状态。
enum TransferStatus { pending, running, done, failed, canceled }

/// 单个传输任务。
class TransferTask {
  TransferTask({
    required this.id,
    required this.isUpload,
    required this.bucket,
    required this.key,
    required this.localPath,
    this.status = TransferStatus.pending,
    this.bytesCompleted = 0,
    this.totalBytes = 0,
    this.speedBytes = 0,
    this.error,
  });

  final String id;
  final bool isUpload;
  final String bucket;
  final String key;
  final String localPath;
  TransferStatus status;
  int bytesCompleted;
  int totalBytes;
  double speedBytes;
  String? error;

  String get displayName => key.split('/').last;
  String get typeLabel => isUpload ? '上传' : '下载';
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
}

/// 全局队列：页面和侧边栏共享。
class TransferQueue extends ChangeNotifier {
  TransferQueue._();

  static final TransferQueue instance = TransferQueue._();

  final List<TransferTask> _tasks = [];
  RemoteStorageGateway? _api;
  Timer? _pollTimer;
  bool _polling = false;
  int _seed = 0;
  final Set<String> _cancelRequestedIds = <String>{};

  List<TransferTask> get tasks => List.unmodifiable(_tasks);
  bool get hasRunning => _tasks.any((task) => task.isRunning || task.isPending);
  int get runningCount =>
      _tasks.where((task) => task.isRunning || task.isPending).length;

  void bindApi(RemoteStorageGateway api) {
    _api = api;
    _ensurePolling();
  }

  TransferTask startTask({
    required bool isUpload,
    required String bucket,
    required String key,
    required String localPath,
  }) {
    final task = TransferTask(
      id: 'transfer_${DateTime.now().microsecondsSinceEpoch}_${_seed++}',
      isUpload: isUpload,
      bucket: bucket,
      key: key,
      localPath: localPath,
    );
    _tasks.insert(0, task);
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
    notifyListeners();
    _ensurePolling();
  }

  Future<void> cancelTask(String id) async {
    final task = _taskById(id);
    if (task == null || !task.isCancelable) return;
    _cancelRequestedIds.add(id);
    task.status = TransferStatus.canceled;
    task.speedBytes = 0;
    task.error = null;
    notifyListeners();
    if (_api != null) {
      await _api!.cancelTransfer(id);
    }
    _ensurePolling();
  }

  bool isCancelRequested(String id) => _cancelRequestedIds.contains(id);

  void refreshFromSnapshots(List<TransferSnapshot> snapshots) {
    for (final snapshot in snapshots) {
      final task = _taskById(snapshot.id) ?? _addRemoteTask(snapshot);
      final nextStatus = _statusFromWire(snapshot.status);
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
      task.bytesCompleted = snapshot.bytesCompleted;
      task.totalBytes = snapshot.totalBytes;
      task.speedBytes = snapshot.speedBytes;
      task.error = snapshot.error;
    }
    notifyListeners();
    _ensurePolling();
  }

  String get uploadSpeedText => _speedTextFor(true);
  String get downloadSpeedText => _speedTextFor(false);

  String get speedSummary {
    final up = uploadSpeedText;
    final down = downloadSpeedText;
    if (up.isEmpty && down.isEmpty) return '暂无任务';
    if (up.isEmpty) return down;
    if (down.isEmpty) return up;
    return '$up  $down';
  }

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
    if (hasRunning) {
      _pollTimer ??= Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => unawaited(pollNow()),
      );
      unawaited(pollNow());
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  TransferTask? _taskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  TransferTask _addRemoteTask(TransferSnapshot snapshot) {
    final task = TransferTask(
      id: snapshot.id,
      isUpload: snapshot.type == 'upload',
      bucket: snapshot.bucket,
      key: snapshot.key,
      localPath: snapshot.localPath,
    );
    _tasks.insert(0, task);
    return task;
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
}

/// 将速率格式化成适合侧边栏展示的短文本。
String formatBytesPerSecond(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

/// 将体积格式化成任务列表中的可读文本。
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
