// Finder 风格文件列表行：以 SVG 图标为主，保留轻量 hover 和分隔线。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 文件管理页的列表项。
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onSecondaryTapDown,
    this.showDivider = true,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onSecondaryTapDown: onSecondaryTapDown,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: showDivider
                  ? Border(bottom: BorderSide(color: dividerColor, width: 0.6))
                  : null,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
