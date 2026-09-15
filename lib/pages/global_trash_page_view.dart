// ignore_for_file: invalid_use_of_protected_member

part of 'global_trash_page.dart';

// 全局回收站视图：将筛选和主体构建拆出，避免主页面文件继续膨胀。

extension _GlobalTrashPageView on _GlobalTrashPageState {
  List<GlobalTrashBrowserEntry> get _filteredEntries {
    if (_searchText.isEmpty) {
      return _entries;
    }
    return _entries
        .where((entry) {
          final haystack = <String>[
            entry.item.name,
            entry.item.originalKey,
          ].join('\n').toLowerCase();
          return haystack.contains(_searchText);
        })
        .toList(growable: false);
  }

  int get _selectedFilteredCount {
    return _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .length;
  }

  Widget buildPage(BuildContext context) {
    final theme = ShadTheme.of(context);
    final filteredEntries = _filteredEntries;
    final selectedFilteredCount = _selectedFilteredCount;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    // Android 对齐文件管理基线：页面级动作(刷新/清空)收进右上角单一
    // 48dp 入口打开的底部抽屉,选中态不隐藏(行级/批量动作在每行 `…`
    // 抽屉里);加载中没有可用动作时入口隐藏。
    final androidSheetActions = _loading
        ? const <MobilePageAction>[]
        : <MobilePageAction>[
            MobilePageAction(
              label: '刷新',
              icon: LucideIcons.refreshCw,
              onPressed: () => unawaited(_loadInitialBucket()),
            ),
            if (_activeBucket != null && _entries.isNotEmpty)
              MobilePageAction(
                label: '清空回收站',
                icon: LucideIcons.trash,
                onPressed: () => unawaited(_clearActiveBucketTrash()),
              ),
          ];
    Widget? androidActionsEntry;
    if (isAndroid && androidSheetActions.isNotEmpty) {
      androidActionsEntry = Semantics(
        label: '回收站操作',
        child: ShadIconButton.ghost(
          width: 48,
          height: 48,
          iconSize: 22,
          icon: Icon(
            LucideIcons.ellipsisVertical,
            color: theme.colorScheme.primary,
          ),
          onPressed: () => unawaited(
            showMobileActionSheet(
              context,
              title: '回收站操作',
              actions: androidSheetActions,
            ),
          ),
        ),
      );
    }

    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 桌面端保持上游行为：标题始终显示。Android 选中态不再切换
            // 标题槽——计数与批量动作由底部动作条承载，标题层级保持稳定。
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '回收站',
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: isAndroid ? 23 : 22,
                    ),
                  ),
                  if (isAndroid) ...[
                    const SizedBox(height: 3),
                    Text(
                      '浏览与恢复已删除的远端文件。',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (androidActionsEntry != null) ...[
              const SizedBox(width: 8),
              androidActionsEntry,
            ],
            // 桌面操作区按内容宽度布局，上限 360px（与 PageHeaderActions
            // 阈值相等）。Expanded 标题吃掉剩余空间，操作区贴右；窄窗口时
            // 操作区拿到的宽度 < 360，内层 LayoutBuilder 触发折叠成「…」菜单。
            if (!isAndroid) ...[
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: GlobalTrashHeaderActions(
                  selectedCount: selectedFilteredCount,
                  loading: _loading,
                  onRefresh: () => unawaited(_loadInitialBucket()),
                  onRestoreSelected: () => unawaited(_restoreSelected()),
                  onDeleteSelected: () => unawaited(_deleteSelected()),
                  onClearTrash:
                      _activeBucket == null || _entries.isEmpty || _loading
                      ? null
                      : () => unawaited(_clearActiveBucketTrash()),
                ),
              ),
            ],
          ],
        ),
        // 头部后间距对齐文件管理移动呈现(14dp),桌面保持 16。
        SizedBox(height: isAndroid ? 14 : 16),
        GlobalTrashFilters(
          searchController: _searchController,
          bucketFilter: _activeBucket ?? '',
          bucketOptions: _bucketOptions,
          onBucketChanged: (value) {
            if (value == null || value.isEmpty) {
              return;
            }
            unawaited(_switchBucket(value));
          },
        ),
        // 与文件管理页一致:搜索框与列表紧贴(12dp)。
        SizedBox(height: isAndroid ? 12 : 16),
        Expanded(child: _buildBody(theme, filteredEntries)),
      ],
    );

    if (isAndroid) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: page,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: page,
    );
  }

  Widget _buildBody(
    ShadThemeData theme,
    List<GlobalTrashBrowserEntry> filteredEntries,
  ) {
    if (_loading) {
      return const Center(
        child: AppLoadingIndicator(size: 22, strokeWidth: 2.4),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 40,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (_activeBucket == null) {
      return Center(
        child: Text(
          '暂无可用存储桶',
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    if (filteredEntries.isEmpty) {
      final text = _entries.isEmpty
          ? '${_activeBucketLabel ?? '当前存储桶'}回收站为空'
          : '当前搜索没有结果';
      return Center(
        child: Text(
          text,
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    return GlobalTrashBrowser(
      entries: filteredEntries,
      scrollController: _scrollController,
      loadingMore: _loadingMore,
      selectedIds: _selectedIds,
      busyIds: _busyEntries,
      // With multi-account aggregation the bucket id is `profile::bucket`,
      // which is not useful to display as a raw column. Hide the per-entry
      // bucket column in the global trash page (the bucket filter dropdown
      // above already lets users switch buckets).
      showBucketColumn: false,
      onToggleSelection: _toggleSelection,
      onToggleSelectAll: _toggleSelectAllFiltered,
      onRestore: (entry) => unawaited(_restoreEntry(entry)),
      onDeletePermanently: (entry) => unawaited(_deleteEntry(entry)),
      // Android 行 `…` 抽屉的批量动作(当前过滤后仍可见的选择)。
      onBatchRestore: () => unawaited(_restoreSelected()),
      onBatchDelete: () => unawaited(_deleteSelected()),
      batchSelectedCount: _selectedFilteredCount,
      onClearSelection: () => setState(_selectedIds.clear),
    );
  }
}
