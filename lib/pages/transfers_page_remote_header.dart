part of 'transfers_page.dart';

// Android 手机窄屏的紧凑头部：隐藏队列标签行（状态下拉已覆盖同样筛选），
// 批量动作收进右上角单一入口打开的底部抽屉。桌面端保持完整队列头部不变。
bool get _androidCompactQueueHeader =>
    defaultTargetPlatform == TargetPlatform.android;

// Queue-level controls act on all durable pending work, independent of row selection.
extension _TransfersPageRemoteHeader on _TransfersPageState {
  Widget _buildRemoteQueueBody(ShadThemeData theme, RemoteTaskStore store) {
    final visible = _filteredRemoteTasks(store);
    final selectedVisible = visible
        .where((task) => _selectedTaskIds.contains(task.id))
        .length;
    final selected = visible
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList(growable: false);
    final cancelable = selected.where((task) => task.cancelable).length;
    final triggerable = selected.where((task) => task.triggerable).length;
    final clearable = selected.where(isRemoteTaskHistory).length;
    final syncable = store.tasks.where(_canBulkSyncRemoteTask).length;
    final historyTotal = store.queue.reported
        ? store.queue.history
        : store.tasks.where(isRemoteTaskHistory).length;
    // Android 对齐文件管理基线：队列级/选中级批量动作不再内联在头部，
    // 收进右上角单一 48dp 入口打开的共享底部抽屉；批处理运行中入口图标
    // 变为 spinner 保留可见反馈，没有可用动作时整个入口隐藏。
    Widget? androidActionsEntry;
    if (_androidCompactQueueHeader) {
      final sheetActions = _runningBatchAction
          ? const <MobilePageAction>[]
          : <MobilePageAction>[
              if (_selectedTaskIds.isEmpty && syncable > 0)
                MobilePageAction(
                  label: '立即同步 $syncable',
                  icon: LucideIcons.play,
                  onPressed: () => unawaited(_triggerAllRemoteTasks(store)),
                ),
              if (_selectedTaskIds.isEmpty && historyTotal > 0)
                MobilePageAction(
                  label: '清理全部历史 $historyTotal',
                  icon: LucideIcons.trash2,
                  onPressed: () => unawaited(_clearRemoteHistory(store)),
                ),
              if (_selectedTaskIds.isNotEmpty && clearable > 0)
                MobilePageAction(
                  label: '清理历史 $clearable',
                  icon: LucideIcons.trash2,
                  onPressed: () => unawaited(
                    _clearSelectedRemoteHistory(store, selected),
                  ),
                ),
            ];
      if (_runningBatchAction || sheetActions.isNotEmpty) {
        androidActionsEntry = Semantics(
          label: '任务操作',
          child: ShadIconButton.ghost(
            width: 48,
            height: 48,
            iconSize: 22,
            icon: _runningBatchAction
                ? const AppLoadingIndicator(size: 22, strokeWidth: 2.4)
                : Icon(
                    LucideIcons.ellipsisVertical,
                    color: theme.colorScheme.primary,
                  ),
            onPressed: _runningBatchAction || sheetActions.isEmpty
                ? null
                : () => unawaited(
                    showMobileActionSheet(
                      context,
                      title: '任务操作',
                      actions: sheetActions,
                    ),
                  ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: _androidCompactQueueHeader
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            // 桌面端保持上游行为：标题始终显示、22 号、无副标题。Android
            // 窄屏在选中任务后把标题槽换成「已选 N 项」，为批量操作按钮
            // 腾出宽度；无选中时按移动基线显示 23 号标题 + 副标题。
            Expanded(
              child: _selectedTaskIds.isEmpty || !_androidCompactQueueHeader
                  ? _androidCompactQueueHeader
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '任务队列',
                                style: theme.textTheme.h3.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 23,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '查看传输与同步任务的进度。',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.mutedForeground,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            '任务队列',
                            style: theme.textTheme.h3.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          )
                  : Text(
                      '已选 ${_selectedTaskIds.length} 项',
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
            if (androidActionsEntry != null) ...[
              const SizedBox(width: 8),
              androidActionsEntry,
            ],
            // 桌面端保持完整队列头部：内联 outline 按钮与原间距不变。
            if (!_androidCompactQueueHeader) ...[
              const SizedBox(width: 10),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _runningBatchAction || syncable == 0
                    ? null
                    : () => unawaited(_triggerAllRemoteTasks(store)),
                child: _batchActionButtonChild(
                  _batchAction == _RemoteBatchAction.sync,
                  syncable == 0 ? '立即同步' : '立即同步 $syncable',
                  loadingLabel: '正在同步…',
                ),
              ),
              if (_selectedTaskIds.isNotEmpty) ...[
                const SizedBox(width: 10),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _runningBatchAction || triggerable == 0
                      ? null
                      : () =>
                            unawaited(_triggerSelectedRemote(store, selected)),
                  child: Text(triggerable == 0 ? '立即执行' : '立即执行 $triggerable'),
                ),
                const SizedBox(width: 6),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _runningBatchAction || cancelable == 0
                      ? null
                      : () => unawaited(_cancelSelectedRemote(store, selected)),
                  child: Text(cancelable == 0 ? '取消' : '取消 $cancelable'),
                ),
                if (clearable > 0) ...[
                  const SizedBox(width: 6),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: _runningBatchAction
                        ? null
                        : () => unawaited(
                            _clearSelectedRemoteHistory(store, selected),
                          ),
                    child: _batchActionButtonChild(
                      _batchAction == _RemoteBatchAction.clearSelectedHistory,
                      '清理历史 $clearable',
                    ),
                  ),
                ],
              ],
              if (historyTotal > 0) ...[
                const SizedBox(width: 10),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _runningBatchAction
                      ? null
                      : () => unawaited(_clearRemoteHistory(store)),
                  child: _batchActionButtonChild(
                    _batchAction == _RemoteBatchAction.clearAllHistory,
                    '清理全部历史 $historyTotal',
                  ),
                ),
              ],
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Android 窄屏不显示队列标签行：状态下拉已提供同样的筛选能力，
        // 这一行只会占用竖向空间。
        if (!_androidCompactQueueHeader) ...[
          _buildRemoteQueueTabs(theme, store),
          const SizedBox(height: 12),
        ],
        _buildRemoteFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildRemoteList(theme, store, visible, selectedVisible),
        ),
      ],
    );
  }
}

// Bulk sync also makes retry-wait work due now; row-level triggerability only
// describes the narrower single-task control and therefore is not sufficient.
bool _canBulkSyncRemoteTask(RemoteTask task) =>
    task.source == RemoteTaskSource.metadata &&
    switch (task.status) {
      RemoteTaskStatus.waiting ||
      RemoteTaskStatus.blocked ||
      RemoteTaskStatus.retryWait => true,
      _ => false,
    };
