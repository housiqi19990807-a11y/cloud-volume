// Bucket browser keeps the bucket-only list/grid rendering out of the page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';

part 'file_manager_bucket_source_actions.dart';
part 'file_manager_bucket_browser_actions.dart';

const String _bucketContextMenuGroup = 'file_manager_bucket_browser';

class FileManagerBucketBrowser extends StatelessWidget {
  static const double _bucketActionColumnWidth = 244;
  static const double _bucketSourceColumnWidth = 172;
  static const double _bucketActionHeaderInset = 14;

  const FileManagerBucketBrowser({
    super.key,
    required this.buckets,
    required this.isGrid,
    required this.gridIconSize,
    required this.listIconSize,
    required this.onOpenBucket,
    required this.mountStatuses,
    required this.busyBuckets,
    this.showActionColumn = true,
    this.actionColumnLabel = '操作',
    this.onOpenTrashBucket,
    this.onConfigureBucket,
    this.onMountBucket,
    this.onUnmountBucket,
    this.onOpenMountedBucket,
    this.onOpenWebDavBucket,
    this.bucketTrashEnabled,
    this.webDavActionLabel = 'WebDAV',
  });

  final List<FileManagerBucketEntry> buckets;
  final bool isGrid;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<FileManagerBucketEntry> onOpenBucket;
  final Map<String, BucketMountStatus> mountStatuses;
  final Set<String> busyBuckets;
  final bool showActionColumn;
  final String actionColumnLabel;
  final ValueChanged<FileManagerBucketEntry>? onOpenTrashBucket;
  final ValueChanged<FileManagerBucketEntry>? onConfigureBucket;
  final ValueChanged<FileManagerBucketEntry>? onMountBucket;
  final ValueChanged<FileManagerBucketEntry>? onUnmountBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenMountedBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenWebDavBucket;
  final bool Function(FileManagerBucketEntry bucket)? bucketTrashEnabled;
  final String webDavActionLabel;

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return _buildGrid();
    }
    return _buildList(context);
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 118).floor().clamp(
          4,
          10,
        );
        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.92,
          children: buckets
              .map(
                (bucket) => _wrapGridBucketWithContextMenu(
                  bucket,
                  FileGridItem(
                    leading: WhiteSurFileIcon(
                      assetPath:
                          'assets/icons/whitesur/places/network-server-balanced.svg',
                      size: gridIconSize,
                    ),
                    title: bucket.bucket.name,
                    subtitle: '',
                    contentWidth: gridIconSize + 12,
                    onTap: () => _handleBucketTap(bucket),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  /// 桶列表列宽随容器收缩：窄屏隐藏「来源/操作」列，名称占满剩余宽度。
  (double sourceW, double actionW, bool showSource, bool showActions)
      _bucketListColumns(double maxWidth) {
    final showActions = showActionColumn && maxWidth >= 620;
    final showSource = maxWidth >= 480;
    final sourceW = showSource
        ? (maxWidth >= 920 ? _bucketSourceColumnWidth : 108.0)
        : 0.0;
    final actionW = showActions
        ? (maxWidth >= 1000 ? _bucketActionColumnWidth : 104.0)
        : 0.0;
    return (sourceW, actionW, showSource, showActions);
  }

  Widget _buildList(BuildContext context) {
    final headerTextStyle = const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _bucketListColumns(constraints.maxWidth);
        final sourceW = cols.$1;
        final actionW = cols.$2;
        final showSource = cols.$3;
        final showActions = cols.$4;

        return ShadCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ShadTheme.of(context)
                          .colorScheme
                          .border
                          .withValues(alpha: 0.75),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(width: listIconSize + 12),
                    const SizedBox(width: 12),
                    Expanded(child: Text('名称', style: headerTextStyle)),
                    if (showSource) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: sourceW,
                        child: Text(
                          '来源',
                          textAlign: TextAlign.right,
                          style: headerTextStyle,
                        ),
                      ),
                    ],
                    if (showActions) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: actionW,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: _bucketActionHeaderInset,
                          ),
                          child: Text(
                            actionColumnLabel,
                            textAlign: TextAlign.left,
                            style: headerTextStyle,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: buckets.length,
                  itemBuilder: (context, index) {
                    final bucket = buckets[index];
                    final trailing = (showSource || showActions)
                        ? _BucketSourceAndActions(
                            sourceLabel: bucket.sourceLabel,
                            showSourceColumn: showSource,
                            showActionColumn: showActions,
                            actionColumnWidth: actionW,
                            sourceColumnWidth: sourceW,
                            child: _BucketMountActions(
                              bucket: bucket,
                              status: mountStatuses[bucket.id],
                              busy: busyBuckets.contains(bucket.id),
                              onMountBucket: onMountBucket,
                              onUnmountBucket: onUnmountBucket,
                              onOpenMountedBucket: onOpenMountedBucket,
                              onConfigureBucket: onConfigureBucket,
                              moreMenuItems: _buildBucketMenuItems(bucket),
                            ),
                          )
                        : null;
                    return _wrapBucketWithContextMenu(
                      bucket,
                      FileListTile(
                        leading: WhiteSurFileIcon(
                          assetPath:
                              'assets/icons/whitesur/places/network-server-balanced.svg',
                          size: listIconSize,
                        ),
                        title: bucket.bucket.name,
                        subtitleLabel:
                            showSource ? '' : bucket.sourceLabel,
                        sizeLabel: '',
                        sizeColumnWidthOverride: 0,
                        onTap: () => _handleBucketTap(bucket),
                        showDivider: index != buckets.length - 1,
                        trailing: trailing,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _wrapGridBucketWithContextMenu(
    FileManagerBucketEntry bucket,
    Widget child,
  ) {
    return _wrapBucketWithContextMenu(bucket, child);
  }

  Widget _wrapBucketWithContextMenu(
    FileManagerBucketEntry bucket,
    Widget child,
  ) {
    final items = _buildBucketMenuItems(bucket);
    if (items.isEmpty) {
      return child;
    }
    return DesktopContextMenuRegion(
      groupId: _bucketContextMenuGroup,
      items: items,
      child: child,
    );
  }

  List<Widget> _buildBucketMenuItems(FileManagerBucketEntry bucket) {
    final status = mountStatuses[bucket.id];
    final busy = busyBuckets.contains(bucket.id);
    final mounted = status?.mounted ?? false;
    final showsWebDavAction = onOpenWebDavBucket != null;
    final trashEnabled =
        bucketTrashEnabled?.call(bucket) ?? onOpenTrashBucket != null;

    return <Widget>[
      ShadContextMenuItem(
        onPressed: () => _runBucketMenuAction(() => onOpenBucket(bucket)),
        child: const Text('打开存储桶'),
      ),
      if (onConfigureBucket != null)
        ShadContextMenuItem(
          onPressed: () =>
              _runBucketMenuAction(() => onConfigureBucket!(bucket)),
          child: const Text('桶设置'),
        ),
      if (showsWebDavAction && !busy) ...[
        if (onOpenTrashBucket != null && trashEnabled)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenTrashBucket!(bucket)),
            child: const Text('打开回收站'),
          ),
        ShadContextMenuItem(
          onPressed: () =>
              _runBucketMenuAction(() => onOpenWebDavBucket!(bucket)),
          child: Text('查看 $webDavActionLabel 地址'),
        ),
      ] else if (mounted && !busy) ...[
        if (onOpenTrashBucket != null && trashEnabled)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenTrashBucket!(bucket)),
            child: const Text('打开回收站'),
          ),
        if (onOpenMountedBucket != null)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenMountedBucket!(bucket)),
            child: const Text('打开挂载目录'),
          ),
        if (onUnmountBucket != null)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onUnmountBucket!(bucket)),
            child: const Text('卸载'),
          ),
      ] else ...[
        if (onOpenTrashBucket != null && trashEnabled)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenTrashBucket!(bucket)),
            child: const Text('打开回收站'),
          ),
        if (!busy && onMountBucket != null)
          ShadContextMenuItem(
            onPressed: () => _runBucketMenuAction(() => onMountBucket!(bucket)),
            child: const Text('挂载'),
          ),
      ],
    ];
  }

  void _handleBucketTap(FileManagerBucketEntry bucket) {
    if (_dismissActiveContextMenu()) {
      return;
    }
    onOpenBucket(bucket);
  }

  bool _dismissActiveContextMenu() {
    return DesktopContextMenuRegistry.dismiss(_bucketContextMenuGroup);
  }

  void _runBucketMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_bucketContextMenuGroup);
    action();
  }
}
