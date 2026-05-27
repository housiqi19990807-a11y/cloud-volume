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
    this.onSelectionTap,
    this.isSelected = false,
    this.showSelectionControl = false,
    this.showDivider = true,
    this.deleting = false,
    this.trailing,
    this.sizeColumnWidthOverride = FileListTile.sizeColumnWidth,
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
  final VoidCallback? onSelectionTap;
  final bool isSelected;
  final bool showSelectionControl;
  final bool showDivider;
  final bool deleting;
  final Widget? trailing;
  final double sizeColumnWidthOverride;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: deleting ? null : onTap,
        onDoubleTap: deleting ? null : onDoubleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: showDivider
                ? Border(bottom: BorderSide(color: dividerColor, width: 0.6))
                : null,
          ),
          child: Row(
            children: [
              if (showSelectionControl) ...[
                _SelectionIndicator(
                  isSelected: isSelected,
                  onTap: onSelectionTap,
                ),
                const SizedBox(width: 10),
              ],
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: onTitleTap,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: deleting
                            ? theme.colorScheme.mutedForeground
                            : theme.colorScheme.foreground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: sizeColumnWidthOverride,
                child: Text(
                  sizeLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: deleting
                        ? theme.colorScheme.primary
                        : theme.colorScheme.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              if (trailing != null)
                trailing!
              else
                SizedBox(
                  width: modifiedColumnWidth,
                  child: Text(
                    modifiedLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: deleting
                          ? theme.colorScheme.primary
                          : theme.colorScheme.mutedForeground,
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

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: isSelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? accent
                : theme.colorScheme.border.withValues(alpha: 0.9),
            width: 1.2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
