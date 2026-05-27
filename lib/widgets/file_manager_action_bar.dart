// 文件管理操作栏：左侧提供当前视图搜索，右侧承载视图和批量操作。

import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final p = theme.colorScheme.primary;
    final inSelectionMode = selectedCount > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (inSelectionMode) ...[
          _selectionBadge(p),
          const SizedBox(width: 6),
          _actionButton(
            label: '批量下载',
            icon: LucideIcons.download,
            color: p,
            onPressed: batchDownloadEnabled ? onBatchDownload : null,
          ),
          const SizedBox(width: 6),
          _actionButton(
            label: '批量删除',
            icon: LucideIcons.trash2,
            color: p,
            onPressed: onBatchDelete,
          ),
          const SizedBox(width: 6),
          _actionButton(
            label: '取消选择',
            icon: LucideIcons.x,
            color: p,
            onPressed: onClearSelection,
          ),
        ] else ...[
          _iconButton(
            icon: isGrid ? LucideIcons.list : LucideIcons.layoutGrid,
            color: p,
            onPressed: onToggleView,
          ),
          if (onOpenTrash != null || onCloseTrash != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: showingTrash ? trashCloseLabel : trashOpenLabel,
              icon: showingTrash ? LucideIcons.folderOpen : LucideIcons.trash2,
              color: p,
              onPressed: showingTrash ? onCloseTrash : onOpenTrash,
            ),
          ],
          if (onMount != null || mounted || mountBusy) ...[
            const SizedBox(width: 6),
            _mountStatusBadge(p),
          ],
          if (onMount != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '挂载',
              icon: LucideIcons.hardDriveDownload,
              color: p,
              onPressed: onMount,
            ),
          ],
          if (mounted && onUnmount != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '卸载',
              icon: LucideIcons.x,
              color: p,
              onPressed: onUnmount,
            ),
          ],
          if (mounted && onOpenMount != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '打开挂载目录',
              icon: LucideIcons.folderOpen,
              color: p,
              onPressed: onOpenMount,
            ),
          ],
          if (onCreateDirectory != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '新建目录',
              icon: Icons.create_new_folder_rounded,
              color: p,
              onPressed: onCreateDirectory,
            ),
          ],
          if (onUpload != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '上传',
              icon: LucideIcons.upload,
              color: p,
              onPressed: onUpload,
            ),
          ],
        ],
      ],
    );
  }

  Widget _selectionBadge(Color p) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '已选 $selectedCount 项',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p),
      ),
    );
  }

  Widget _mountStatusBadge(Color p) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mountBusy) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: p),
            ),
            const SizedBox(width: 8),
          ] else
            Icon(
              mounted ? LucideIcons.hardDriveDownload : LucideIcons.link,
              size: 14,
              color: p,
            ),
          const SizedBox(width: 6),
          Text(
            mountBusy
                ? '正在处理挂载'
                : mounted
                ? '桌面已挂载'
                : '未挂载',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p,
            ),
          ),
        ],
      ),
    );
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
