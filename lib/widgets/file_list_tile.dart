// Finder 风格文件列表行：左侧名称，右侧固定尺寸/修改时间列。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 文件管理页的列表项。
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.leading,
    required this.title,
    this.sizeLabel = '',
    this.modifiedLabel = '',
    required this.onTap,
    this.onDoubleTap,
    this.onTitleTap,
    this.isSelected = false,
    this.showDivider = true,
  });

  static const double sizeColumnWidth = 96;
  static const double modifiedColumnWidth = 154;

  final Widget leading;
  final String title;
  final String sizeLabel;
  final String modifiedLabel;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTitleTap;
  final bool isSelected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: showDivider
                ? Border(bottom: BorderSide(color: dividerColor, width: 0.6))
                : null,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTitleTap,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: sizeColumnWidth,
                child: Text(
                  sizeLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: modifiedColumnWidth,
                child: Text(
                  modifiedLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
