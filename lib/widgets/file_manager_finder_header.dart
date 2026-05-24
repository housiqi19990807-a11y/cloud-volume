// Finder 风格头部：左侧后退/前进与当前目录名，点目录名后展开面包屑，右侧保留操作按钮。

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerFinderHeader extends StatelessWidget {
  const FileManagerFinderHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.activeBucket,
    required this.breadcrumbs,
    required this.isGrid,
    required this.canGoBack,
    required this.canGoForward,
    required this.showBreadcrumbs,
    required this.onToggleBreadcrumbs,
    required this.onGoBack,
    required this.onGoForward,
    required this.onOpenBucketList,
    required this.onOpenBucketRoot,
    required this.onOpenCrumb,
    required this.onToggleView,
    this.onCreateDirectory,
    this.onUpload,
  });

  final ShadThemeData theme;
  final String title;
  final String? activeBucket;
  final List<String> breadcrumbs;
  final bool isGrid;
  final bool canGoBack;
  final bool canGoForward;
  final bool showBreadcrumbs;
  final VoidCallback onToggleBreadcrumbs;
  final VoidCallback onGoBack;
  final VoidCallback onGoForward;
  final VoidCallback onOpenBucketList;
  final VoidCallback onOpenBucketRoot;
  final ValueChanged<int> onOpenCrumb;
  final VoidCallback onToggleView;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _navButton(
              icon: LucideIcons.chevronLeft,
              enabled: canGoBack,
              onPressed: onGoBack,
            ),
            const SizedBox(width: 4),
            _navButton(
              icon: LucideIcons.chevronRight,
              enabled: canGoForward,
              onPressed: onGoForward,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: activeBucket == null ? null : onToggleBreadcrumbs,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: activeBucket == null
                          ? Colors.transparent
                          : theme.colorScheme.secondary.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.foreground,
                            ),
                          ),
                        ),
                        if (activeBucket != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            showBreadcrumbs
                                ? LucideIcons.chevronUp
                                : LucideIcons.chevronDown,
                            size: 14,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FileManagerActionBar(
                  theme: theme,
                  isGrid: isGrid,
                  onToggleView: onToggleView,
                  onCreateDirectory: onCreateDirectory,
                  onUpload: onUpload,
                ),
              ),
            ),
          ],
        ),
        if (showBreadcrumbs) ...[
          const SizedBox(height: 10),
          FileManagerBreadcrumbBar(
            theme: theme,
            activeBucket: activeBucket,
            breadcrumbs: breadcrumbs,
            onOpenBucketList: onOpenBucketList,
            onOpenBucketRoot: onOpenBucketRoot,
            onOpenCrumb: onOpenCrumb,
          ),
        ],
      ],
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: enabled ? onPressed : null,
      child: Icon(
        icon,
        size: 14,
        color: enabled
            ? theme.colorScheme.foreground
            : theme.colorScheme.mutedForeground.withValues(alpha: 0.45),
      ),
    );
  }
}
