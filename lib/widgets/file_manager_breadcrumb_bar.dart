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
    final visibleCrumbs = _visibleCrumbs();
    final hiddenCrumbs = _hiddenCrumbs();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
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
          _crumbLabel(
            activeBucket!,
            onTap: onOpenBucketRoot,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            maxWidth: 170,
          ),
          if (hiddenCrumbs.isNotEmpty) ...[
            _crumbChevron(theme),
            PopupMenuButton<int>(
              tooltip: '展开中间层级',
              padding: EdgeInsets.zero,
              offset: const Offset(0, 28),
              itemBuilder: (context) => [
                for (final crumb in hiddenCrumbs)
                  PopupMenuItem<int>(
                    value: crumb.index,
                    child: Text(crumb.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onSelected: onOpenCrumb,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  '...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ),
          ],
          for (final crumb in visibleCrumbs) ...[
            _crumbChevron(theme),
            _crumbLabel(
              crumb.label,
              onTap: () => onOpenCrumb(crumb.index),
              color: crumb.index == breadcrumbs.length - 1
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
              fontWeight: crumb.index == breadcrumbs.length - 1
                  ? FontWeight.w600
                  : FontWeight.w400,
              maxWidth: crumb.index == breadcrumbs.length - 1 ? 200 : 140,
            ),
          ],
        ],
      ),
    );
  }

  List<_CrumbEntry> _visibleCrumbs() {
    if (breadcrumbs.length <= 3) {
      return [
        for (int i = 0; i < breadcrumbs.length; i++)
          _CrumbEntry(index: i, label: breadcrumbs[i]),
      ];
    }
    return [
      _CrumbEntry(index: 0, label: breadcrumbs.first),
      _CrumbEntry(index: breadcrumbs.length - 1, label: breadcrumbs.last),
    ];
  }

  List<_CrumbEntry> _hiddenCrumbs() {
    if (breadcrumbs.length <= 3) return const [];
    return [
      for (int i = 1; i < breadcrumbs.length - 1; i++)
        _CrumbEntry(index: i, label: breadcrumbs[i]),
    ];
  }

  Widget _crumbLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
    required FontWeight fontWeight,
    required double maxWidth,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: fontWeight, color: color),
        ),
      ),
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

class _CrumbEntry {
  const _CrumbEntry({required this.index, required this.label});

  final int index;
  final String label;
}
