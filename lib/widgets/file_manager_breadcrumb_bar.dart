// 文件管理面包屑：负责显示首页、桶和目录层级，并提供对应跳转入口。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerBreadcrumbBar extends StatelessWidget {
  const FileManagerBreadcrumbBar({
    super.key,
    required this.theme,
    required this.activeBucket,
    required this.breadcrumbs,
    required this.onOpenBucketList,
    required this.onOpenBucketRoot,
    required this.onOpenCrumb,
  });

  final ShadThemeData theme;
  final String? activeBucket;
  final List<String> breadcrumbs;
  final VoidCallback onOpenBucketList;
  final VoidCallback onOpenBucketRoot;
  final ValueChanged<int> onOpenCrumb;

  @override
  Widget build(BuildContext context) {
    if (activeBucket == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文件管理',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '浏览和管理远程存储中的文件。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        GestureDetector(
          onTap: onOpenBucketList,
          child: Icon(
            LucideIcons.house,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        _crumbChevron(theme),
        GestureDetector(
          onTap: onOpenBucketRoot,
          child: Text(
            activeBucket!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        for (int i = 0; i < breadcrumbs.length; i++) ...[
          _crumbChevron(theme),
          GestureDetector(
            onTap: () => onOpenCrumb(i),
            child: Text(
              breadcrumbs[i],
              style: TextStyle(
                fontSize: 14,
                fontWeight: i == breadcrumbs.length - 1
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: i == breadcrumbs.length - 1
                    ? theme.colorScheme.foreground
                    : theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _crumbChevron(ShadThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        LucideIcons.chevronRight,
        size: 14,
        color: theme.colorScheme.mutedForeground,
      ),
    );
  }
}
