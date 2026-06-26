// 文件同步任务页：展示所有同步配置的概览状态以及由同步产生的实时任务。
// 与通用任务队列互补——这里只显示 sync_ 类型的任务，并提供立即同步入口。
import 'package:flutter/material.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileSyncTasksPage extends StatefulWidget {
  const FileSyncTasksPage({
    super.key,
    required this.api,
    required this.config,
    this.active = false,
  });

  final RemoteStorageGateway api;
  final dynamic config;
  final bool active;

  @override
  State<FileSyncTasksPage> createState() => _FileSyncTasksPageState();
}

class _FileSyncTasksPageState extends State<FileSyncTasksPage> {
  @override
  void initState() {
    super.initState();
    TransferQueue.instance.addListener(_onQueueChanged);
    SyncProfileNotifier.instance.addListener(_onProfilesChanged);
  }

  @override
  void dispose() {
    TransferQueue.instance.removeListener(_onQueueChanged);
    SyncProfileNotifier.instance.removeListener(_onProfilesChanged);
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  void _onProfilesChanged() {
    if (mounted) setState(() {});
  }

  List<TransferTask> get _syncTasks =>
      TransferQueue.instance.tasks.where((t) => t.isSyncTask).toList();

  Future<void> _triggerSync(SyncProfileRuntime runtime) async {
    try {
      final ops = await SyncProfileNotifier.instance
          .triggerProfile(runtime.profile.id);
      if (!mounted) return;
      showAppToast(context, message: ops > 0 ? '已触发，共 $ops 个操作' : '已是最新');
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '同步失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final profiles = SyncProfileNotifier.instance.profiles;
    final tasks = _syncTasks;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '文件同步任务',
              style: theme.textTheme.h3.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '查看同步配置状态，以及由同步产生的上传、下载、删除、重命名任务。',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            _summaryCards(theme, profiles, tasks),
            const SizedBox(height: 24),
            Text(
              '同步配置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 12),
            if (profiles.isEmpty)
              _emptyHint(theme, '还没有同步配置，请到系统设置中新建。')
            else
              ...profiles.map((p) => _profileRow(theme, p)),
            const SizedBox(height: 28),
            Text(
              '同步任务（${tasks.length}）',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              _emptyHint(theme, '暂无同步任务。同步触发后会在此显示。')
            else
              ...tasks.map((t) => _taskRow(theme, t)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCards(
    ShadThemeData theme,
    List<SyncProfileRuntime> profiles,
    List<TransferTask> tasks,
  ) {
    final enabled = profiles.where((p) => p.profile.enabled).length;
    final syncing =
        profiles.where((p) => p.status == SyncProfileStatus.syncing).length;
    final running = tasks.where((t) => t.status == TransferStatus.running).length;
    final failed = tasks.where((t) => t.status == TransferStatus.failed).length;
    return Row(
      children: [
        _statCard(theme, LucideIcons.refreshCw, '$enabled', '已启用配置'),
        const SizedBox(width: 12),
        _statCard(theme, LucideIcons.loader, '$syncing', '同步中'),
        const SizedBox(width: 12),
        _statCard(theme, LucideIcons.arrowDownUp, '$running', '执行中任务'),
        const SizedBox(width: 12),
        _statCard(theme, LucideIcons.alertCircle, '$failed', '失败任务'),
      ],
    );
  }

  Widget _statCard(
    ShadThemeData theme,
    IconData icon,
    String value,
    String label,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileRow(ShadThemeData theme, SyncProfileRuntime runtime) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      runtime.profile.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusDot(theme, runtime.status),
                    const SizedBox(width: 6),
                    Text(
                      runtime.status.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${runtime.profile.direction.label} · '
                  '${runtime.pendingOps} 待处理 · 上次 ${runtime.lastSyncAt.isEmpty ? '未同步' : runtime.lastSyncAt}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          ShadButton.outline(
            onPressed: () => _triggerSync(runtime),
            child: const Text('立即同步'),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(ShadThemeData theme, TransferTask task) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _taskKindIcon(theme, task),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.key,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.foreground,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_syncTypeLabel(task)} · ${task.status.name}'
                  '${task.totalBytes > 0 ? ' · ${formatBytes(task.bytesCompleted)}/${formatBytes(task.totalBytes)}' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                if (task.error != null && task.error!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    task.error!,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.destructive,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskKindIcon(ShadThemeData theme, TransferTask task) {
    final icon = switch (task.rawType) {
      'sync_upload' => LucideIcons.upload,
      'sync_download' => LucideIcons.download,
      'sync_delete' => LucideIcons.trash2,
      'sync_rename' => LucideIcons.pencilLine,
      _ => LucideIcons.refreshCw,
    };
    return Icon(icon, size: 16, color: theme.colorScheme.primary);
  }

  String _syncTypeLabel(TransferTask task) {
    return switch (task.rawType) {
      'sync_upload' => '同步上传',
      'sync_download' => '同步下载',
      'sync_delete' => '同步删除',
      'sync_rename' => '同步重命名',
      _ => '同步',
    };
  }

  Widget _statusDot(ShadThemeData theme, SyncProfileStatus status) {
    final color = switch (status) {
      SyncProfileStatus.syncing => theme.colorScheme.primary,
      SyncProfileStatus.error => theme.colorScheme.destructive,
      SyncProfileStatus.paused => theme.colorScheme.mutedForeground,
      SyncProfileStatus.idle => theme.colorScheme.primary,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _emptyHint(ShadThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}
