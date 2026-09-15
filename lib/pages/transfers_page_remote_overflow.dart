part of 'transfers_page.dart';

// Android 任务行 `…` 抽屉的动作装配:无选中/单个选中时为该行自身可用
// 动作,本行已选中且选中数 >1 时为当前选择的批量动作(文件管理抽屉
// 契约,含「取消选择」)。拆出以守住 transfers_page_remote.dart 的
// 500 行上限。

extension _TransfersPageRemoteOverflow on _TransfersPageState {
  /// Android 行尾 `…` 抽屉(文件管理契约);批处理运行中动作集为空。
  RemoteTaskOverflow? _taskRowOverflowActions(
    RemoteTaskStore store,
    RemoteTask task,
    List<RemoteTask> visible,
  ) {
    if (_runningBatchAction) {
      return const RemoteTaskOverflow(title: '', actions: []);
    }
    final selected = visible
        .where((item) => _selectedTaskIds.contains(item.id))
        .toList(growable: false);
    // 批量抽屉按文件管理正典触发:当前行已选中且选中数 >1;单个选中
    // 的批量等价于该行自身动作,走行级分支。
    if (selected.length > 1 && _selectedTaskIds.contains(task.id)) {
      final triggerable = selected.where((item) => item.triggerable).length;
      final cancelable = selected.where((item) => item.cancelable).length;
      final clearable = selected.where(isRemoteTaskHistory).length;
      return RemoteTaskOverflow(
        title: '已选 ${selected.length} 个任务',
        actions: [
          MobilePageAction(
            label: '取消选择',
            icon: LucideIcons.x,
            onPressed: () => _remoteSetState(_selectedTaskIds.clear),
          ),
          if (triggerable > 0)
            MobilePageAction(
              label: '立即执行 $triggerable',
              icon: LucideIcons.play,
              onPressed: () => unawaited(
                _triggerSelectedRemote(store, selected),
              ),
            ),
          if (cancelable > 0)
            MobilePageAction(
              label: '取消任务 $cancelable',
              icon: LucideIcons.circleX,
              onPressed: () => unawaited(
                _cancelSelectedRemote(store, selected),
              ),
            ),
          if (clearable > 0)
            MobilePageAction(
              label: '清理历史 $clearable',
              icon: LucideIcons.trash2,
              onPressed: () => unawaited(
                _clearSelectedRemoteHistory(store, selected),
              ),
            ),
        ],
      );
    }
    return RemoteTaskOverflow(
      title: remoteTaskEntryName(task),
      actions: [
        if (task.triggerable)
          MobilePageAction(
            label: '立即执行',
            icon: LucideIcons.play,
            onPressed: () => unawaited(_triggerRemoteTask(store, task)),
          ),
        if (task.cancelable)
          MobilePageAction(
            label: '取消任务',
            icon: LucideIcons.circleX,
            onPressed: () => unawaited(_cancelRemoteTask(store, task)),
          ),
        if (task.retryable)
          MobilePageAction(
            label: '重试',
            icon: LucideIcons.refreshCw,
            onPressed: () => unawaited(_retryRemoteTask(store, task)),
          ),
        if (isRemoteTaskHistory(task))
          MobilePageAction(
            label: '清理历史',
            icon: LucideIcons.trash2,
            onPressed: () => unawaited(
              _clearSelectedRemoteHistory(store, [task]),
            ),
          ),
      ],
    );
  }

  // Queue-tab row switches the list between status queues; each tab is a
  // dedicated StatefulWidget per the hover binding rule.
  Widget _buildRemoteQueueTabs(ShadThemeData theme, RemoteTaskStore store) {
    final tasks = store.tasks;
    final serverQueue = store.queue;
    final hasServerCounts = serverQueue.reported;
    int count(_RemoteTaskStatusFilter filter) {
      // Prefer server-reported unpaged counts; loaded rows are only a
      // fallback for older binaries that omit the queue field.
      if (hasServerCounts) {
        return switch (filter) {
          _RemoteTaskStatusFilter.all => serverQueue.total,
          _RemoteTaskStatusFilter.active => serverQueue.active,
          _RemoteTaskStatusFilter.waiting => serverQueue.waiting,
          _RemoteTaskStatusFilter.failed => serverQueue.failed,
          _RemoteTaskStatusFilter.history => serverQueue.history,
        };
      }
      return tasks
          .where(
            (task) =>
                filter == _RemoteTaskStatusFilter.all || filter.matches(task),
          )
          .length;
    }

    return Row(
      children: [
        for (final filter in _RemoteTaskStatusFilter.values) ...[
          _RemoteQueueTab(
            label: filter.label,
            count: count(filter),
            selected: filter == _remoteStatusFilter,
            onTap: () => _remoteSetState(() => _remoteStatusFilter = filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}
