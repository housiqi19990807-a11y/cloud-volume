// 任务队列页：展示对象操作与挂载写回任务，并提供筛选、批量操作和时间线信息。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/transfer_task_widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'transfers_page_retry.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({
    super.key,
    required this.api,
    required this.config,
    this.active = false,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final bool active;

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedTaskIds = <String>{};
  String _searchText = '';
  _TransferStatusFilter _statusFilter = _TransferStatusFilter.all;
  _TransferKindFilter _kindFilter = _TransferKindFilter.all;
  bool _runningBatchAction = false;

  @override
  void initState() {
    super.initState();
    TransferQueue.instance.addListener(_syncSelectionWithQueue);
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    TransferQueue.instance.removeListener(_syncSelectionWithQueue);
    _searchController.dispose();
    super.dispose();
  }

  void _syncSelectionWithQueue() {
    final taskIds = TransferQueue.instance.tasks.map((task) => task.id).toSet();
    final before = _selectedTaskIds.length;
    _selectedTaskIds.removeWhere((id) => !taskIds.contains(id));
    if (_selectedTaskIds.length != before && mounted) {
      setState(() {});
    }
  }

  void _toggleTaskSelection(String id) {
    setState(() {
      if (!_selectedTaskIds.remove(id)) {
        _selectedTaskIds.add(id);
      }
    });
  }

  void _toggleVisibleSelection(List<TransferTask> tasks) {
    final visibleIds = tasks.map((task) => task.id).toSet();
    final shouldSelectAll = visibleIds.any(
      (id) => !_selectedTaskIds.contains(id),
    );
    setState(() {
      if (shouldSelectAll) {
        _selectedTaskIds.addAll(visibleIds);
      } else {
        _selectedTaskIds.removeAll(visibleIds);
      }
    });
  }

  void _clearSelection() {
    if (_selectedTaskIds.isEmpty) {
      return;
    }
    setState(_selectedTaskIds.clear);
  }

  Future<void> _startSelectedTasks(TransferQueue queue) async {
    if (_runningBatchAction) {
      return;
    }
    setState(() => _runningBatchAction = true);
    try {
      final triggered = await queue.triggerTasksNow(_selectedTaskIds);
      if (!mounted) {
        return;
      }
      if (triggered == 0) {
        showAppToast(context, message: '当前选中没有可立即同步的任务；只有“等待同步”的任务可以立即同步。');
        return;
      }
      showAppToast(context, title: '已批量开始', message: '已开始 $triggered 个等待同步任务。');
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '批量开始失败', message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _runningBatchAction = false);
      }
    }
  }

  Future<void> _cancelSelectedTasks(TransferQueue queue) async {
    if (_runningBatchAction) {
      return;
    }
    setState(() => _runningBatchAction = true);
    try {
      final canceled = await queue.cancelTasks(_selectedTaskIds);
      if (!mounted) {
        return;
      }
      if (canceled == 0) {
        showAppToast(context, message: '当前选中没有可取消的任务。');
        return;
      }
      showAppToast(context, title: '已批量取消', message: '已取消 $canceled 个任务。');
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '批量取消失败', message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _runningBatchAction = false);
      }
    }
  }

  void _removeSelectedTasks(TransferQueue queue) {
    if (_runningBatchAction) {
      return;
    }
    setState(() => _runningBatchAction = true);
    try {
      final removed = queue.removeTasks(_selectedTaskIds);
      if (!mounted) {
        return;
      }
      if (removed == 0) {
        showAppToast(context, message: '当前选中没有可移除的记录；只有已完成的任务可以移除。');
        _clearSelectionMaybe();
        return;
      }
      setState(_selectedTaskIds.clear);
      showAppToast(context, title: '已移除记录', message: '已移除 $removed 条已完成记录。');
    } finally {
      if (mounted) {
        setState(() => _runningBatchAction = false);
      }
    }
  }

  Future<void> _confirmClearFinished(TransferQueue queue) async {
    if (_runningBatchAction) {
      return;
    }
    final finishedCount = queue.taskView.where(_isRemovableFinished).length;
    if (finishedCount == 0) {
      showAppToast(context, message: '当前没有已完成的任务可以清空。');
      return;
    }
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('清空已完成记录'),
        description: Text('将删除 $finishedCount 条已完成/失败/取消的记录，不会影响实际文件。'),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  ShadButton.destructive(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _runningBatchAction = true);
    try {
      final removed = queue.clearFinished();
      if (mounted) {
        setState(_selectedTaskIds.clear);
        if (removed > 0) {
          showAppToast(
            context,
            title: '已清空记录',
            message: '已清空 $removed 条已完成记录。',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _runningBatchAction = false);
      }
    }
  }

  bool _isRemovableFinished(TransferTask task) => task.isFinished && !task.isDirectoryChild;

  void _clearSelectionMaybe() {
    // No-op hook; kept for symmetry with future auto-clear on filter changes.
  }

  void _removeTask(TransferTask task, TransferQueue queue) {
    final removed = queue.removeTask(task.id);
    if (!mounted) return;
    if (removed) {
      setState(() => _selectedTaskIds.remove(task.id));
      showAppToast(context, message: '已从记录移除 “${task.displayName}”。');
    } else {
      showAppToast(context, message: '该任务尚未结束，无法移除。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final queue = TransferQueue.instance;
    final body = widget.active
        ? AnimatedBuilder(
            animation: queue,
            builder: (context, _) => _buildQueueBody(theme, queue),
          )
        : _buildQueueBody(theme, queue);
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: body,
    );
  }

  Widget _buildQueueBody(ShadThemeData theme, TransferQueue queue) {
    final selectedCount = _selectedTaskIds.length;
    final visibleTasks = _filteredTasks(queue);
    final selectedVisibleCount = visibleTasks
        .where((task) => _selectedTaskIds.contains(task.id))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '任务队列',
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '查看上传、下载、复制、移动、删除，以及等待同步到远端的挂载写回任务。',
                    style: TextStyle(
                      color: theme.colorScheme.mutedForeground,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TransferTaskSelectionActions(
                  selectedCount: selectedCount,
                  selectedVisibleCount: selectedVisibleCount,
                  startableCount: queue.triggerableTaskCount(_selectedTaskIds),
                  cancelableCount: queue.cancelableTaskCount(_selectedTaskIds),
                  removableCount: queue.removableTaskCount(_selectedTaskIds),
                  runningBatchAction: _runningBatchAction,
                  onStartSelected: () => unawaited(_startSelectedTasks(queue)),
                  onCancelSelected: () =>
                      unawaited(_cancelSelectedTasks(queue)),
                  onRemoveSelected: () => _removeSelectedTasks(queue),
                  onClearSelection: _clearSelection,
                ),
              ),
            if (queue.taskView.any(_isRemovableFinished))
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _runningBatchAction
                      ? null
                      : () => unawaited(_confirmClearFinished(queue)),
                  child: const Text('清空已完成'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFilters(),
        const SizedBox(height: 16),
        Expanded(child: _buildList(theme, queue, visibleTasks)),
      ],
    );
  }

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: _searchController,
            placeholder: const Text('搜索文件名、路径、存储桶或目标路径'),
          ),
        ),
        const SizedBox(width: 12),
        _dropdown<_TransferStatusFilter>(
          value: _statusFilter,
          items: _TransferStatusFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _statusFilter = value);
          },
          width: 140,
        ),
        const SizedBox(width: 12),
        _dropdown<_TransferKindFilter>(
          value: _kindFilter,
          items: _TransferKindFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _kindFilter = value);
          },
          width: 140,
        ),
      ],
    );
  }

  Widget _buildList(
    ShadThemeData theme,
    TransferQueue queue,
    List<TransferTask> filteredTasks,
  ) {
    if (queue.tasks.isEmpty) {
      return _buildEmptyState(
        theme,
        '暂无任务',
        '在文件管理页发起上传、下载、复制、移动、删除，或通过已挂载云卷读写文件后，任务会显示在这里。',
      );
    }
    if (filteredTasks.isEmpty) {
      return _buildEmptyState(theme, '没有匹配结果', '调整筛选条件后再试。');
    }
    final allVisibleSelected =
        filteredTasks.isNotEmpty &&
        filteredTasks.every((task) => _selectedTaskIds.contains(task.id));
    final partiallySelected =
        filteredTasks.any((task) => _selectedTaskIds.contains(task.id)) &&
        !allVisibleSelected;
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          TransferTaskListHeader(
            totalCount: filteredTasks.length,
            speedSummary: queue.speedSummary,
            allVisibleSelected: allVisibleSelected,
            partiallySelected: partiallySelected,
            onToggleVisibleSelection: () =>
                _toggleVisibleSelection(filteredTasks),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredTasks.length,
              itemBuilder: (context, index) {
                final task = filteredTasks[index];
                return TransferTaskRow(
                  task: task,
                  subtitle: _subtitleFor(task),
                  selected: _selectedTaskIds.contains(task.id),
                  onToggleSelected: () => _toggleTaskSelection(task.id),
                  showDivider: index != filteredTasks.length - 1,
                  onCancelPressed: queue.canCancelTask(task.id)
                      ? () => unawaited(queue.cancelTask(task.id))
                      : null,
                  onStartNowPressed: queue.canTriggerTask(task.id)
                      ? () => unawaited(queue.triggerTaskNow(task.id))
                      : null,
                  onRetryPressed: task.isRetryableFileTransfer
                      ? () => unawaited(_retryFileTransfer(task))
                      : null,
                  onRemovePressed: queue.canRemoveTask(task.id)
                      ? () => _removeTask(task, queue)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilters(TransferTask task) {
    if (!_statusFilter.matches(task) || !_kindFilter.matches(task)) {
      return false;
    }
    if (_searchText.isEmpty) {
      return true;
    }
    final haystack = <String>[
      task.displayName,
      task.bucket,
      task.key,
      task.targetPath,
      task.localPath,
      task.typeLabel,
    ].join('\n').toLowerCase();
    return haystack.contains(_searchText);
  }

  List<TransferTask> _filteredTasks(TransferQueue queue) {
    return queue.taskView.where(_matchesFilters).toList(growable: false);
  }

  Widget _buildEmptyState(ShadThemeData theme, String title, String detail) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_vert,
            size: 48,
            color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T value) labelBuilder,
    required ValueChanged<T?> onChanged,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: ShadSelect<T>(
        key: ValueKey<Object>(value as Object),
        minWidth: width,
        initialValue: value,
        placeholder: Text(labelBuilder(value)),
        selectedOptionBuilder: (context, selected) =>
            Text(labelBuilder(selected)),
        options: items
            .map(
              (item) =>
                  ShadOption<T>(value: item, child: Text(labelBuilder(item))),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }

  String _subtitleFor(TransferTask task) {
    final createdAtLabel = formatTransferCreatedAt(task.createdAt);
    if (task.status == TransferStatus.failed) {
      return _joinSubtitleParts([
        task.error ?? '${task.typeLabel}失败',
        createdAtLabel,
      ]);
    }
    if (task.status == TransferStatus.canceled) {
      return _joinSubtitleParts(['${task.typeLabel}已取消', createdAtLabel]);
    }
    if (task.status == TransferStatus.pending && task.isUpload) {
      return _joinSubtitleParts([
        task.isUploadWaiting
            ? task.totalBytes > 0
                  ? '等待可用上传协程  ${formatBytes(task.totalBytes)}'
                  : '等待可用上传协程'
            : task.totalBytes > 0
            ? '等待同步到远端  ${formatBytes(task.totalBytes)}'
            : '等待同步到远端',
        createdAtLabel,
      ]);
    }
    if ((task.isCopy || task.isMove) && task.targetPath.isNotEmpty) {
      final suffix = task.totalBytes > 0
          ? '  ${formatBytes(task.bytesCompleted)} / ${formatBytes(task.totalBytes)}'
          : '';
      return _joinSubtitleParts([
        '${task.typeLabel}到 ${task.targetPath}$suffix',
        createdAtLabel,
      ]);
    }
    if (task.totalBytes > 0) {
      final progressLabel =
          '${task.typeLabel}  ${formatBytes(task.bytesCompleted)} / ${formatBytes(task.totalBytes)}';
      return _joinSubtitleParts([
        progressLabel,
        task.progressTargetLabel,
        createdAtLabel,
      ]);
    }
    if (task.status == TransferStatus.done) {
      return _joinSubtitleParts(['${task.typeLabel}已完成', createdAtLabel]);
    }
    return _joinSubtitleParts(['${task.typeLabel}中', createdAtLabel]);
  }
}

String _joinSubtitleParts(List<String> parts) {
  return parts.where((part) => part.trim().isNotEmpty).join('  ·  ');
}

enum _TransferStatusFilter {
  all('全部状态'),
  active('进行中'),
  pending('等待中'),
  running('运行中'),
  done('已完成'),
  failed('失败'),
  canceled('已取消');

  const _TransferStatusFilter(this.label);
  final String label;

  bool matches(TransferTask task) {
    return switch (this) {
      _TransferStatusFilter.all => true,
      _TransferStatusFilter.active =>
        task.status == TransferStatus.pending ||
            task.status == TransferStatus.running,
      _TransferStatusFilter.pending => task.status == TransferStatus.pending,
      _TransferStatusFilter.running => task.status == TransferStatus.running,
      _TransferStatusFilter.done => task.status == TransferStatus.done,
      _TransferStatusFilter.failed => task.status == TransferStatus.failed,
      _TransferStatusFilter.canceled => task.status == TransferStatus.canceled,
    };
  }
}

enum _TransferKindFilter {
  all('全部类型'),
  upload('上传'),
  download('下载'),
  copy('复制'),
  move('移动'),
  delete('删除'),
  appUpdate('应用更新');

  const _TransferKindFilter(this.label);
  final String label;

  bool matches(TransferTask task) {
    return switch (this) {
      _TransferKindFilter.all => true,
      _TransferKindFilter.upload => task.isUpload,
      _TransferKindFilter.download => task.isDownload,
      _TransferKindFilter.copy => task.isCopy,
      _TransferKindFilter.move => task.isMove,
      _TransferKindFilter.delete => task.isDelete,
      _TransferKindFilter.appUpdate => task.isAppUpdate,
    };
  }
}
