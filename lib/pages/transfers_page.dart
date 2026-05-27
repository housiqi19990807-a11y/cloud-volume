// 任务队列页：展示上传、下载、复制、移动、删除以及挂载写回等待任务。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key, required this.api, required this.config});

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  _TransferStatusFilter _statusFilter = _TransferStatusFilter.all;
  _TransferKindFilter _kindFilter = _TransferKindFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final queue = TransferQueue.instance;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36),
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
            '查看上传、下载、复制、移动、删除，以及等待同步到远端的挂载任务。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          _buildFilters(theme),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedBuilder(
              animation: queue,
              builder: (context, _) => _buildList(theme, queue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(ShadThemeData theme) {
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

  Widget _buildList(ShadThemeData theme, TransferQueue queue) {
    final filteredTasks = queue.tasks
        .where(_matchesFilters)
        .toList(growable: false);

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

    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Text(
                  '共 ${filteredTasks.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                const Spacer(),
                Text(
                  queue.speedSummary,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: filteredTasks.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: theme.colorScheme.border),
              itemBuilder: (context, index) {
                final task = filteredTasks[index];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  leading: Icon(
                    _iconFor(task),
                    size: 18,
                    color: _colorFor(task),
                  ),
                  title: Text(
                    task.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                  subtitle: Text(
                    _subtitleFor(task),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (task.isCancelable)
                        IconButton(
                          tooltip: '取消任务',
                          iconSize: 16,
                          splashRadius: 16,
                          onPressed: () => unawaited(
                            TransferQueue.instance.cancelTask(task.id),
                          ),
                          icon: Icon(
                            LucideIcons.circleX,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      if (task.status == TransferStatus.pending &&
                          task.isUpload)
                        IconButton(
                          tooltip: '立即同步',
                          iconSize: 16,
                          splashRadius: 16,
                          onPressed: () => unawaited(
                            TransferQueue.instance.triggerTaskNow(task.id),
                          ),
                          icon: Icon(
                            LucideIcons.play,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      _StatusBadge(task: task),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilters(TransferTask task) {
    if (!_statusFilter.matches(task)) {
      return false;
    }
    if (!_kindFilter.matches(task)) {
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
    if (task.status == TransferStatus.failed) {
      return task.error ?? '${task.typeLabel}失败';
    }
    if (task.status == TransferStatus.canceled) {
      return '${task.typeLabel}已取消';
    }
    if (task.status == TransferStatus.pending && task.isUpload) {
      if (task.totalBytes > 0) {
        return '等待同步到远端  ${formatBytes(task.totalBytes)}';
      }
      return '等待同步到远端';
    }
    if ((task.isCopy || task.isMove) && task.targetPath.isNotEmpty) {
      final suffix = task.totalBytes > 0
          ? '  ${formatBytes(task.bytesCompleted)} / ${formatBytes(task.totalBytes)}'
          : '';
      return '${task.typeLabel}到 ${task.targetPath}$suffix';
    }
    if (task.totalBytes > 0) {
      return '${task.typeLabel}  ${formatBytes(task.bytesCompleted)} / ${formatBytes(task.totalBytes)}';
    }
    if (task.status == TransferStatus.done) {
      return '${task.typeLabel}已完成';
    }
    return '${task.typeLabel}中';
  }

  IconData _iconFor(TransferTask task) {
    if (task.isUpload) return LucideIcons.upload;
    if (task.isDownload) return LucideIcons.download;
    if (task.isCopy) return LucideIcons.copy;
    if (task.isDelete) return LucideIcons.trash2;
    return LucideIcons.moveRight;
  }

  Color _colorFor(TransferTask task) {
    if (task.isUpload) return const Color(0xff2563eb);
    if (task.isDownload) return const Color(0xff0f766e);
    if (task.isCopy) return const Color(0xff7c3aed);
    if (task.isDelete) return const Color(0xffdc2626);
    return const Color(0xffc2410c);
  }
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
    switch (this) {
      case _TransferStatusFilter.all:
        return true;
      case _TransferStatusFilter.active:
        return task.status == TransferStatus.pending ||
            task.status == TransferStatus.running;
      case _TransferStatusFilter.pending:
        return task.status == TransferStatus.pending;
      case _TransferStatusFilter.running:
        return task.status == TransferStatus.running;
      case _TransferStatusFilter.done:
        return task.status == TransferStatus.done;
      case _TransferStatusFilter.failed:
        return task.status == TransferStatus.failed;
      case _TransferStatusFilter.canceled:
        return task.status == TransferStatus.canceled;
    }
  }
}

enum _TransferKindFilter {
  all('全部类型'),
  upload('上传'),
  download('下载'),
  copy('复制'),
  move('移动'),
  delete('删除');

  const _TransferKindFilter(this.label);

  final String label;

  bool matches(TransferTask task) {
    switch (this) {
      case _TransferKindFilter.all:
        return true;
      case _TransferKindFilter.upload:
        return task.isUpload;
      case _TransferKindFilter.download:
        return task.isDownload;
      case _TransferKindFilter.copy:
        return task.isCopy;
      case _TransferKindFilter.move:
        return task.isMove;
      case _TransferKindFilter.delete:
        return task.isDelete;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final text = switch (task.status) {
      TransferStatus.pending => task.isUpload ? '等待同步' : '等待中',
      TransferStatus.running =>
        task.speedBytes > 0
            ? formatBytesPerSecond(task.speedBytes)
            : '${task.typeLabel}中',
      TransferStatus.done => '已完成',
      TransferStatus.failed => '失败',
      TransferStatus.canceled => '已取消',
    };
    final color = switch (task.status) {
      TransferStatus.pending => theme.colorScheme.mutedForeground,
      TransferStatus.running => theme.colorScheme.primary,
      TransferStatus.done => const Color(0xff15803d),
      TransferStatus.failed => theme.colorScheme.destructive,
      TransferStatus.canceled => theme.colorScheme.mutedForeground,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
