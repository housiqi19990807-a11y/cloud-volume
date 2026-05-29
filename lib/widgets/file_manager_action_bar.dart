// 文件管理操作栏：集中展示搜索、挂载状态和常用动作。

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerActionBar extends StatelessWidget {
  const FileManagerActionBar({
    super.key,
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    this.searchController,
    this.searchPlaceholder = '搜索',
    this.searchEnabled = true,
    this.selectedCount = 0,
    this.batchDownloadEnabled = false,
    this.showingTrash = false,
    this.onCreateDirectory,
    this.onUpload,
    this.onOpenTrash,
    this.onCloseTrash,
    this.trashOpenLabel = '回收站',
    this.trashCloseLabel = '返回文件',
    this.onBatchDownload,
    this.onBatchDelete,
    this.onClearSelection,
    this.mounted = false,
    this.mountBusy = false,
    this.onMount,
    this.onUnmount,
    this.onOpenMount,
    this.mountBucketName,
  });

  final ShadThemeData theme;
  final bool isGrid;
  final VoidCallback onToggleView;
  final TextEditingController? searchController;
  final String searchPlaceholder;
  final bool searchEnabled;
  final int selectedCount;
  final bool batchDownloadEnabled;
  final bool showingTrash;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onOpenTrash;
  final VoidCallback? onCloseTrash;
  final String trashOpenLabel;
  final String trashCloseLabel;
  final VoidCallback? onBatchDownload;
  final VoidCallback? onBatchDelete;
  final VoidCallback? onClearSelection;
  final bool mounted;
  final bool mountBusy;
  final VoidCallback? onMount;
  final VoidCallback? onUnmount;
  final VoidCallback? onOpenMount;
  final String? mountBucketName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (searchController != null) ...[
          SizedBox(
            width: 320,
            child: ShadInput(
              controller: searchController,
              enabled: searchEnabled,
              placeholder: Text(searchPlaceholder),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: _ActionButtons(
                theme: theme,
                isGrid: isGrid,
                onToggleView: onToggleView,
                selectedCount: selectedCount,
                batchDownloadEnabled: batchDownloadEnabled,
                showingTrash: showingTrash,
                onCreateDirectory: onCreateDirectory,
                onUpload: onUpload,
                onOpenTrash: onOpenTrash,
                onCloseTrash: onCloseTrash,
                trashOpenLabel: trashOpenLabel,
                trashCloseLabel: trashCloseLabel,
                onBatchDownload: onBatchDownload,
                onBatchDelete: onBatchDelete,
                onClearSelection: onClearSelection,
                mounted: mounted,
                mountBusy: mountBusy,
                onMount: onMount,
                onUnmount: onUnmount,
                onOpenMount: onOpenMount,
                mountBucketName: mountBucketName,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    required this.selectedCount,
    required this.batchDownloadEnabled,
    required this.showingTrash,
    required this.onCreateDirectory,
    required this.onUpload,
    required this.onOpenTrash,
    required this.onCloseTrash,
    required this.trashOpenLabel,
    required this.trashCloseLabel,
    required this.onBatchDownload,
    required this.onBatchDelete,
    required this.onClearSelection,
    required this.mounted,
    required this.mountBusy,
    required this.onMount,
    required this.onUnmount,
    required this.onOpenMount,
    required this.mountBucketName,
  });

  final ShadThemeData theme;
  final bool isGrid;
  final VoidCallback onToggleView;
  final int selectedCount;
  final bool batchDownloadEnabled;
  final bool showingTrash;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onOpenTrash;
  final VoidCallback? onCloseTrash;
  final String trashOpenLabel;
  final String trashCloseLabel;
  final VoidCallback? onBatchDownload;
  final VoidCallback? onBatchDelete;
  final VoidCallback? onClearSelection;
  final bool mounted;
  final bool mountBusy;
  final VoidCallback? onMount;
  final VoidCallback? onUnmount;
  final VoidCallback? onOpenMount;
  final String? mountBucketName;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final inSelectionMode = selectedCount > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (inSelectionMode) ...[
          _selectionBadge(primary),
          const SizedBox(width: 6),
          _actionButton(
            label: '批量下载',
            icon: LucideIcons.download,
            color: primary,
            onPressed: batchDownloadEnabled ? onBatchDownload : null,
          ),
          const SizedBox(width: 6),
          _actionButton(
            label: '批量删除',
            icon: LucideIcons.trash2,
            color: primary,
            onPressed: onBatchDelete,
          ),
          const SizedBox(width: 6),
          _actionButton(
            label: '取消选择',
            icon: LucideIcons.x,
            color: primary,
            onPressed: onClearSelection,
          ),
        ] else ...[
          _iconButton(
            icon: isGrid ? LucideIcons.list : LucideIcons.layoutGrid,
            color: primary,
            onPressed: onToggleView,
          ),
          if (onOpenTrash != null || onCloseTrash != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: showingTrash ? trashCloseLabel : trashOpenLabel,
              icon: showingTrash ? LucideIcons.folderOpen : LucideIcons.trash2,
              color: primary,
              onPressed: showingTrash ? onCloseTrash : onOpenTrash,
            ),
          ],
          if (onMount != null || mounted || mountBusy) ...[
            const SizedBox(width: 6),
            _mountStatusBadge(primary),
          ],
          if (onMount != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '挂载',
              icon: LucideIcons.hardDriveDownload,
              color: primary,
              onPressed: onMount,
            ),
          ],
          if (mounted && onUnmount != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '卸载',
              icon: LucideIcons.x,
              color: primary,
              onPressed: onUnmount,
            ),
          ],
          if (mounted && onOpenMount != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '打开挂载目录',
              icon: LucideIcons.folderOpen,
              color: primary,
              onPressed: onOpenMount,
            ),
          ],
          if (onCreateDirectory != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '新建目录',
              icon: Icons.create_new_folder_rounded,
              color: primary,
              onPressed: onCreateDirectory,
            ),
          ],
          if (onUpload != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '上传',
              icon: LucideIcons.upload,
              color: primary,
              onPressed: onUpload,
            ),
          ],
        ],
      ],
    );
  }

  Widget _selectionBadge(Color color) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '已选 $selectedCount 项',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _mountStatusBadge(Color color) {
    return AnimatedBuilder(
      animation: TransferQueue.instance,
      builder: (context, _) {
        final syncSummary = _mountSyncSummary();
        return Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mountBusy) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: AppLoadingIndicator(strokeWidth: 1.6, color: color),
                ),
                const SizedBox(width: 8),
              ] else
                Icon(
                  mounted ? LucideIcons.hardDriveDownload : LucideIcons.link,
                  size: 14,
                  color: color,
                ),
              const SizedBox(width: 6),
              Text(
                mountBusy
                    ? '正在处理挂载'
                    : syncSummary == null
                    ? (mounted ? '桌面已挂载' : '未挂载')
                    : '已挂载 · $syncSummary',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Only mount-writeback uploads are shown here so the badge reflects
  // delayed sync work coming from the mounted desktop view.
  String? _mountSyncSummary() {
    if (!mounted || mountBucketName == null || mountBucketName!.trim().isEmpty) {
      return null;
    }
    var pending = 0;
    var running = 0;
    for (final task in TransferQueue.instance.tasks) {
      if (!task.id.startsWith('mount-writeback-')) {
        continue;
      }
      if (!task.isUpload || task.bucket != mountBucketName) {
        continue;
      }
      switch (task.status) {
        case TransferStatus.pending:
          pending++;
        case TransferStatus.running:
          running++;
        case TransferStatus.done:
        case TransferStatus.failed:
        case TransferStatus.canceled:
          break;
      }
    }
    if (running > 0 && pending > 0) {
      return '同步中 $running / 等待 $pending';
    }
    if (running > 0) {
      return '同步中 $running';
    }
    if (pending > 0) {
      return '等待同步 $pending';
    }
    return null;
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Icon(icon, size: 14, color: color),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
    );
  }
}
