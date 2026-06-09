part of 'transfer_queue.dart';

// Transfer metrics summarize live queue speeds for sidebar and status text.

extension TransferQueueMetrics on TransferQueue {
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
