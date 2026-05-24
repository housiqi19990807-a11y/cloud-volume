// 文件管理操作栏：将视图切换和目录操作独立成单独一行，避免和面包屑拥挤。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerActionBar extends StatelessWidget {
  const FileManagerActionBar({
    super.key,
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    this.onCreateDirectory,
    this.onUpload,
    this.onGoBack,
  });

  final ShadThemeData theme;
  final bool isGrid;
  final VoidCallback onToggleView;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) {
    final p = theme.colorScheme.primary;
    return Row(
      children: [
        const Spacer(),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onToggleView,
              child: Icon(
                isGrid ? LucideIcons.list : LucideIcons.layoutGrid,
                size: 14,
                color: p,
              ),
            ),
            if (onCreateDirectory != null)
              ShadButton.outline(
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
            if (onUpload != null)
              ShadButton.outline(
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
            if (onGoBack != null)
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onGoBack,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.arrowLeft, size: 14, color: p),
                    const SizedBox(width: 5),
                    const Text('返回'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
