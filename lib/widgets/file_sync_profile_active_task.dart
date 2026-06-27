// 在同步配置卡片内展示该配置当前最新的一条进行中的队列任务。

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 从同步任务 id（`sync-<profileId>-<relPath>`）解析配置 id。
String? syncProfileIdFromTaskId(String taskId) {
  if (!taskId.startsWith('sync-')) return null;
  final body = taskId.substring(5);
  final renameIdx = body.indexOf('-rename-');
  if (renameIdx > 0) {
    return body.substring(0, renameIdx);
  }
  final dash = body.indexOf('-');
  if (dash <= 0) return null;
  return body.substring(0, dash);
}

/// 队列按最新插入在前；返回该配置下第一条 pending/running 的同步任务。
TransferTask? latestActiveSyncTaskForProfile(
  Iterable<TransferTask> syncTasks,
  String profileId,
) {
  final prefix = 'sync-$profileId-';
  for (final task in syncTasks) {
    if (!task.isSyncTask || !task.id.startsWith(prefix)) continue;
    if (task.status == TransferStatus.running ||
        task.status == TransferStatus.pending) {
      return task;
    }
  }
  return null;
}

/// 配置卡片内的单行「当前任务」摘要。
class FileSyncProfileActiveTaskLine extends StatelessWidget {
  const FileSyncProfileActiveTaskLine({super.key, required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final icon = switch (task.rawType) {
      'sync_upload' => LucideIcons.upload,
      'sync_download' => LucideIcons.download,
      'sync_delete' => LucideIcons.trash2,
      'sync_rename' => LucideIcons.pencilLine,
      'sync_mkdir' => LucideIcons.folderPlus,
      _ => LucideIcons.refreshCw,
    };
    final typeLabel = switch (task.rawType) {
      'sync_upload' => '同步上传',
      'sync_download' => '同步下载',
      'sync_delete' => '同步删除',
      'sync_rename' => '同步重命名',
      'sync_mkdir' => '同步建目录',
      _ => '同步',
    };
    final progress = task.totalBytes > 0
        ? ' · ${formatBytes(task.bytesCompleted)}/${formatBytes(task.totalBytes)}'
        : '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前任务：$typeLabel · ${task.displayName}$progress',
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.foreground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            task.status == TransferStatus.running ? '执行中' : '排队中',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
