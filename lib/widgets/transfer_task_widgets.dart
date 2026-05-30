// Transfer task widgets keep the transfers page focused on filtering and bulk actions.

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TransferSelectionToggle extends StatelessWidget {
  const TransferSelectionToggle({
    super.key,
    required this.selected,
    required this.onTap,
    this.partiallySelected = false,
    this.enabled = true,
  });

  final bool selected;
  final bool partiallySelected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final activeColor = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    final borderColor = selected || partiallySelected
        ? activeColor
        : theme.colorScheme.border;
    final background = selected || partiallySelected
        ? activeColor.withValues(alpha: enabled ? 0.12 : 0.06)
        : Colors.transparent;
    final icon = selected
        ? LucideIcons.check
        : partiallySelected
        ? LucideIcons.minus
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        child: icon == null ? null : Icon(icon, size: 12, color: activeColor),
      ),
    );
  }
}

class TransferStatusBadge extends StatelessWidget {
  const TransferStatusBadge({super.key, required this.task});

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

class TransferTaskRow extends StatelessWidget {
  const TransferTaskRow({
    super.key,
    required this.task,
    required this.subtitle,
    required this.selected,
    required this.onToggleSelected,
    this.onCancelPressed,
    this.onStartNowPressed,
  });

  final TransferTask task;
  final String subtitle;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback? onCancelPressed;
  final VoidCallback? onStartNowPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accentColor = _colorFor(task);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TransferSelectionToggle(
              selected: selected,
              onTap: onToggleSelected,
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_iconFor(task), size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
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
                    color: theme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onCancelPressed != null)
                AppTooltip(
                  message: '取消任务',
                  child: ShadIconButton.ghost(
                    icon: Icon(
                      LucideIcons.circleX,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    width: 28,
                    height: 28,
                    iconSize: 16,
                    onPressed: onCancelPressed,
                  ),
                ),
              if (onStartNowPressed != null)
                AppTooltip(
                  message: '立即同步',
                  child: ShadIconButton.ghost(
                    icon: Icon(
                      LucideIcons.play,
                      color: theme.colorScheme.primary,
                    ),
                    width: 28,
                    height: 28,
                    iconSize: 16,
                    onPressed: onStartNowPressed,
                  ),
                ),
              const SizedBox(width: 8),
              TransferStatusBadge(task: task),
            ],
          ),
        ],
      ),
    );
  }
}

class TransferTaskSelectionActions extends StatelessWidget {
  const TransferTaskSelectionActions({
    super.key,
    required this.selectedCount,
    required this.selectedVisibleCount,
    required this.startableCount,
    required this.cancelableCount,
    required this.runningBatchAction,
    required this.onStartSelected,
    required this.onCancelSelected,
    required this.onClearSelection,
  });

  final int selectedCount;
  final int selectedVisibleCount;
  final int startableCount;
  final int cancelableCount;
  final bool runningBatchAction;
  final VoidCallback onStartSelected;
  final VoidCallback onCancelSelected;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _selectionSummary(
              selectedCount: selectedCount,
              selectedVisibleCount: selectedVisibleCount,
            ),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (runningBatchAction)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '处理中…',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: runningBatchAction || startableCount == 0
              ? null
              : onStartSelected,
          child: Text(startableCount > 0 ? '批量开始 $startableCount' : '批量开始'),
        ),
        ShadButton.destructive(
          size: ShadButtonSize.sm,
          onPressed: runningBatchAction || cancelableCount == 0
              ? null
              : onCancelSelected,
          child: Text(cancelableCount > 0 ? '批量取消 $cancelableCount' : '批量取消'),
        ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: runningBatchAction ? null : onClearSelection,
          child: const Text('清空选择'),
        ),
      ],
    );
  }
}

class TransferTaskListHeader extends StatelessWidget {
  const TransferTaskListHeader({
    super.key,
    required this.totalCount,
    required this.speedSummary,
    required this.allVisibleSelected,
    required this.partiallySelected,
    required this.onToggleVisibleSelection,
  });

  final int totalCount;
  final String speedSummary;
  final bool allVisibleSelected;
  final bool partiallySelected;
  final VoidCallback onToggleVisibleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Text(
            '共 $totalCount 条',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onToggleVisibleSelection,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TransferSelectionToggle(
                    selected: allVisibleSelected,
                    partiallySelected: partiallySelected,
                    onTap: onToggleVisibleSelection,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    allVisibleSelected ? '取消全选当前结果' : '全选当前结果',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            speedSummary,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

String _selectionSummary({
  required int selectedCount,
  required int selectedVisibleCount,
}) {
  if (selectedVisibleCount == selectedCount) {
    return '已选 $selectedCount 项';
  }
  return '已选 $selectedCount 项，当前筛选中 $selectedVisibleCount 项';
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
