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
    final currentCrumb = _currentCrumb();
    final hiddenCrumbs = _hiddenCrumbs();
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 32,
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
            Flexible(
              fit: FlexFit.loose,
              child: _crumbLabel(
                activeBucket!,
                onTap: onOpenBucketRoot,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hiddenCrumbs.isNotEmpty) ...[
              _crumbChevron(theme),
              _hiddenCrumbMenu(hiddenCrumbs),
            ],
            if (currentCrumb != null) ...[
              _crumbChevron(theme),
              Expanded(
                child: _crumbLabel(
                  currentCrumb.label,
                  onTap: () => onOpenCrumb(currentCrumb.index),
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _CrumbEntry? _currentCrumb() {
    if (breadcrumbs.isEmpty) {
      return null;
    }
    return _CrumbEntry(index: breadcrumbs.length - 1, label: breadcrumbs.last);
  }

  List<_CrumbEntry> _hiddenCrumbs() {
    if (breadcrumbs.length <= 1) return const [];
    return [
      for (int i = 0; i < breadcrumbs.length - 1; i++)
        _CrumbEntry(index: i, label: breadcrumbs[i]),
    ];
  }

  Widget _hiddenCrumbMenu(List<_CrumbEntry> hiddenCrumbs) {
    return PopupMenuButton<int>(
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
    );
  }

  Widget _crumbLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
    required FontWeight fontWeight,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, fontWeight: fontWeight, color: color),
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
