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
    this.onCreateDirectory,
    this.onUpload,
    this.onBatchDownload,
    this.onBatchDelete,
    this.onClearSelection,
  });

  final ShadThemeData theme;
  final bool isGrid;
  final VoidCallback onToggleView;
  final int selectedCount;
  final bool batchDownloadEnabled;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onBatchDownload;
  final VoidCallback? onBatchDelete;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final p = theme.colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (selectedCount > 0) ...[
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
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: onToggleView,
            child: Icon(
              isGrid ? LucideIcons.list : LucideIcons.layoutGrid,
              size: 14,
              color: p,
            ),
          ),
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
      ),
    );
  }
}
