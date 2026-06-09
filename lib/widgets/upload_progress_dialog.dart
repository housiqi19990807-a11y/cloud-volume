// Upload progress dialog keeps drag, paste, and picker uploads on one unified modal.

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/transfer_task_widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class UploadProgressDialog extends StatelessWidget {
  const UploadProgressDialog({
    super.key,
    required this.taskIds,
    required this.currentPathLabel,
    required this.onRunInBackground,
    required this.onClose,
  });

  final List<String> taskIds;
  final String currentPathLabel;
  final VoidCallback onRunInBackground;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TransferQueue.instance,
      builder: (context, _) {
        final queue = TransferQueue.instance;
        final tasks = queue.tasks
            .where((task) => taskIds.contains(task.id))
            .toList(growable: false);
        final finishedCount = tasks.where((task) => task.isFinished).length;
        final failedCount = tasks
            .where((task) => task.status == TransferStatus.failed)
            .length;
        final activeCount = tasks.length - finishedCount;
        final allFinished = tasks.isNotEmpty && activeCount == 0;
        final totalBytes = tasks.fold<int>(
          0,
          (sum, task) => task.totalBytes > 0 ? sum + task.totalBytes : sum,
        );
        final completedBytes = tasks.fold<int>(
          0,
          (sum, task) => sum + task.bytesCompleted,
        );
        final totalSpeed = tasks.fold<double>(
          0,
          (sum, task) => sum + task.speedBytes,
        );
        final totalItems = tasks.fold<int>(
          0,
          (sum, task) => sum + task.totalItems,
        );
        final completedItems = tasks.fold<int>(
          0,
          (sum, task) => sum + task.itemsCompleted,
        );
        final progress = totalBytes > 0
            ? (completedBytes / totalBytes).clamp(0.0, 1.0)
            : null;

        return ShadDialog(
          title: Text(allFinished ? '上传完成' : '正在上传'),
          description: Text(
            _description(
              totalCount: tasks.length,
              activeCount: activeCount,
              failedCount: failedCount,
              allFinished: allFinished,
            ),
          ),
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryCard(
                  currentPathLabel: currentPathLabel,
                  totalCount: tasks.length,
                  activeCount: activeCount,
                  failedCount: failedCount,
                  progress: progress,
                  completedBytes: completedBytes,
                  totalBytes: totalBytes,
                  completedItems: completedItems,
                  totalItems: totalItems,
                  totalSpeed: totalSpeed,
                  allFinished: allFinished,
                ),
                const SizedBox(height: 14),
                if (tasks.isNotEmpty) _TaskList(tasks: tasks),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: onClose,
                      child: Text(allFinished ? '关闭' : '稍后查看'),
                    ),
                    if (!allFinished) ...[
                      const SizedBox(width: 10),
                      ShadButton.outline(
                        onPressed: () => _cancelActiveTasks(tasks),
                        child: const Text('取消上传'),
                      ),
                      const SizedBox(width: 10),
                      ShadButton(
                        onPressed: onRunInBackground,
                        child: const Text('后台运行'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _cancelActiveTasks(List<TransferTask> tasks) {
    for (final task in tasks.where((task) => task.isCancelable)) {
      TransferQueue.instance.cancelTask(task.id);
    }
  }

  String _description({
    required int totalCount,
    required int activeCount,
    required int failedCount,
    required bool allFinished,
  }) {
    if (allFinished) {
      if (failedCount > 0) {
        return '共处理 $totalCount 个上传任务，其中 $failedCount 个失败。';
      }
      return '共处理 $totalCount 个上传任务，全部已完成。';
    }
    if (failedCount > 0) {
      return '还有 $activeCount 个任务进行中，$failedCount 个任务失败。';
    }
    return '当前有 $activeCount 个上传任务正在进行，可关闭弹框后继续后台上传。';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.currentPathLabel,
    required this.totalCount,
    required this.activeCount,
    required this.failedCount,
    required this.progress,
    required this.completedBytes,
    required this.totalBytes,
    required this.completedItems,
    required this.totalItems,
    required this.totalSpeed,
    required this.allFinished,
  });

  final String currentPathLabel;
  final int totalCount;
  final int activeCount;
  final int failedCount;
  final double? progress;
  final int completedBytes;
  final int totalBytes;
  final int completedItems;
  final int totalItems;
  final double totalSpeed;
  final bool allFinished;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (allFinished)
                Icon(
                  LucideIcons.circleCheckBig,
                  size: 18,
                  color: const Color(0xff15803d),
                )
              else
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppLoadingIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentPathLabel.isEmpty ? '当前目录' : currentPathLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: theme.colorScheme.background,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _metaChip(theme, '$totalCount 个任务'),
              if (!allFinished) _metaChip(theme, '进行中 $activeCount'),
              if (failedCount > 0)
                _metaChip(
                  theme,
                  '失败 $failedCount',
                  color: theme.colorScheme.destructive,
                ),
              if (totalBytes > 0)
                _metaChip(
                  theme,
                  '${formatBytes(completedBytes)} / ${formatBytes(totalBytes)}',
                ),
              if (totalItems > 0)
                _metaChip(theme, '$completedItems / $totalItems 个文件'),
              if (!allFinished && totalSpeed > 0)
                _metaChip(theme, formatBytesPerSecond(totalSpeed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(ShadThemeData theme, String text, {Color? color}) {
    final foreground = color ?? theme.colorScheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});

  final List<TransferTask> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: tasks.length,
        separatorBuilder: (_, index) => Divider(
          height: 1,
          thickness: 0.6,
          color: theme.colorScheme.border.withValues(alpha: 0.65),
        ),
        itemBuilder: (context, index) {
          final task = tasks[index];
          final subtitle = _subtitleFor(task);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  LucideIcons.upload,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TransferStatusBadge(task: task),
                if (task.isCancelable) ...[
                  const SizedBox(width: 8),
                  ShadIconButton.ghost(
                    icon: Icon(
                      LucideIcons.circleX,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    width: 30,
                    height: 30,
                    iconSize: 16,
                    onPressed: () => TransferQueue.instance.cancelTask(task.id),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _subtitleFor(TransferTask task) {
    final parts = <String>[task.key];
    if (task.totalItems > 0) {
      parts.add('${task.itemsCompleted} / ${task.totalItems} 个文件');
    } else if (task.statusDetail == 'scanning') {
      parts.add('正在扫描文件');
    }
    if (task.totalBytes > 0) {
      parts.add(formatBytes(task.totalBytes));
    }
    if (task.progressTargetLabel.isNotEmpty) {
      parts.add(task.progressTargetLabel);
    }
    return parts.join('  ·  ');
  }
}
