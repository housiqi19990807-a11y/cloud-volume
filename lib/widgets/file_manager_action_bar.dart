// 文件管理操作栏：将视图切换和目录操作独立成单独一行，避免和面包屑拥挤。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerActionBar extends StatelessWidget {
  const FileManagerActionBar({
    super.key,
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    this.selectedCount = 0,
    this.batchDownloadEnabled = false,
    this.showingTrash = false,
    this.onCreateDirectory,
    this.onUpload,
    this.onOpenTrash,
    this.onCloseTrash,
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
  final int selectedCount;
  final bool batchDownloadEnabled;
  final bool showingTrash;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onOpenTrash;
  final VoidCallback? onCloseTrash;
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (inSelectionMode) ...[
            Container(
              height: 32,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '已选 $selectedCount 项',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: batchDownloadEnabled ? onBatchDownload : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.download, size: 14, color: p),
                  const SizedBox(width: 5),
                  const Text('批量下载'),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: onBatchDelete,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.trash2, size: 14, color: p),
                  const SizedBox(width: 5),
                  const Text('批量删除'),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: onClearSelection,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.x, size: 14, color: p),
                  const SizedBox(width: 5),
                  const Text('取消选择'),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (!inSelectionMode) ...[
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: onToggleView,
              child: Icon(
                isGrid ? LucideIcons.list : LucideIcons.layoutGrid,
                size: 14,
                color: p,
              ),
            ),
            if (onOpenTrash != null || onCloseTrash != null) ...[
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: showingTrash ? onCloseTrash : onOpenTrash,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showingTrash
                          ? LucideIcons.folderOpen
                          : LucideIcons.trash2,
                      size: 14,
                      color: p,
                    ),
                    const SizedBox(width: 5),
                    Text(showingTrash ? '返回文件' : '回收站'),
                  ],
                ),
              ),
            ],
            if (onMount != null || mounted || mountBusy) ...[
              const SizedBox(width: 6),
              Container(
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
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: p,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else
                      Icon(
                        mounted
                            ? LucideIcons.hardDriveDownload
                            : LucideIcons.link,
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
              ),
            ],
            if (onMount != null) ...[
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onMount,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.hardDriveDownload, size: 14, color: p),
                    const SizedBox(width: 5),
                    const Text('挂载'),
                  ],
                ),
              ),
            ],
            if (mounted && onUnmount != null) ...[
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onUnmount,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.x, size: 14, color: p),
                    const SizedBox(width: 5),
                    const Text('卸载'),
                  ],
                ),
              ),
            ],
            if (mounted && onOpenMount != null) ...[
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onOpenMount,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.folderOpen, size: 14, color: p),
                    const SizedBox(width: 5),
                    const Text('打开挂载目录'),
                  ],
                ),
              ),
            ],
            if (onCreateDirectory != null) ...[
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onCreateDirectory,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.create_new_folder_rounded, size: 15, color: p),
                    const SizedBox(width: 5),
                    const Text('新建目录'),
                  ],
                ),
              ),
            ],
            if (onUpload != null) ...[
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onUpload,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.upload, size: 14, color: p),
                    const SizedBox(width: 5),
                    const Text('上传'),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
