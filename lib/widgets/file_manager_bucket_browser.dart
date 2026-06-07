// Bucket browser keeps the bucket-only list/grid rendering out of the page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';

part 'file_manager_bucket_source_actions.dart';

const String _bucketContextMenuGroup = 'file_manager_bucket_browser';

class FileManagerBucketBrowser extends StatelessWidget {
  static const double _bucketActionColumnWidth = 172;
  static const double _bucketTypeColumnWidth = 72;
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
    required this.sourceLabel,
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

  final List<BucketInfo> buckets;
  final bool isGrid;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<String> onOpenBucket;
  final Map<String, BucketMountStatus> mountStatuses;
  final Set<String> busyBuckets;
  final String sourceLabel;
  final bool showActionColumn;
  final String actionColumnLabel;
  final ValueChanged<String>? onOpenTrashBucket;
  final ValueChanged<String>? onConfigureBucket;
  final ValueChanged<String>? onMountBucket;
  final ValueChanged<String>? onUnmountBucket;
  final ValueChanged<String>? onOpenMountedBucket;
  final ValueChanged<String>? onOpenWebDavBucket;
  final bool Function(String bucket)? bucketTrashEnabled;
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
                  bucket.name,
                  FileGridItem(
                    leading: WhiteSurFileIcon(
                      assetPath:
                          'assets/icons/whitesur/places/network-server-balanced.svg',
                      size: gridIconSize,
                    ),
                    title: bucket.name,
                    subtitle: '',
                    contentWidth: gridIconSize + 12,
                    onTap: () => _handleBucketTap(bucket.name),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final headerTextStyle = const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );

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
                  color: ShadTheme.of(
                    context,
                  ).colorScheme.border.withValues(alpha: 0.75),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: listIconSize + 12),
                const SizedBox(width: 12),
                Expanded(child: Text('名称', style: headerTextStyle)),
                const SizedBox(width: 12),
                SizedBox(
                  width: _bucketTypeColumnWidth,
                  child: Text(
                    '类型',
                    textAlign: TextAlign.right,
                    style: headerTextStyle,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: _bucketSourceColumnWidth,
                  child: Text(
                    '来源',
                    textAlign: TextAlign.right,
                    style: headerTextStyle,
                  ),
                ),
                if (showActionColumn) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: _bucketActionColumnWidth,
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
                return _wrapBucketWithContextMenu(
                  bucket.name,
                  FileListTile(
                    leading: WhiteSurFileIcon(
                      assetPath:
                          'assets/icons/whitesur/places/network-server-balanced.svg',
                      size: listIconSize,
                    ),
                    title: bucket.name,
                    sizeLabel: '存储桶',
                    sizeColumnWidthOverride: _bucketTypeColumnWidth,
                    onTap: () => _handleBucketTap(bucket.name),
                    showDivider: index != buckets.length - 1,
                    trailing: _BucketSourceAndActions(
                      sourceLabel: sourceLabel,
                      showActionColumn: showActionColumn,
                      actionColumnWidth: _bucketActionColumnWidth,
                      sourceColumnWidth: _bucketSourceColumnWidth,
                      child: _BucketMountActions(
                        bucket: bucket.name,
                        status: mountStatuses[bucket.name],
                        busy: busyBuckets.contains(bucket.name),
                        onMountBucket: onMountBucket,
                        onUnmountBucket: onUnmountBucket,
                        moreMenuItems: _buildBucketMenuItems(bucket.name),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapGridBucketWithContextMenu(String bucket, Widget child) {
    return _wrapBucketWithContextMenu(bucket, child);
  }

  Widget _wrapBucketWithContextMenu(String bucket, Widget child) {
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

  List<Widget> _buildBucketMenuItems(String bucket) {
    final status = mountStatuses[bucket];
    final busy = busyBuckets.contains(bucket);
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

  void _handleBucketTap(String bucket) {
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

class _BucketMountActions extends StatelessWidget {
  static const double _actionButtonWidth = 76;

  const _BucketMountActions({
    required this.bucket,
    required this.status,
    required this.busy,
    required this.onMountBucket,
    required this.onUnmountBucket,
    required this.moreMenuItems,
  });

  final String bucket;
  final BucketMountStatus? status;
  final bool busy;
  final ValueChanged<String>? onMountBucket;
  final ValueChanged<String>? onUnmountBucket;
  final List<Widget> moreMenuItems;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mounted = status?.mounted ?? false;
    final foreground = theme.colorScheme.primary;
    final primaryAction = mounted ? onUnmountBucket : onMountBucket;

    if (busy) {
      return SizedBox(
        height: 32,
        child: Row(
          children: [
            _actionSlot(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: AppLoadingIndicator(
                      strokeWidth: 1.5,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '处理中',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _actionSlot(
              _miniButton(
                label: '更多',
                icon: LucideIcons.ellipsisVertical,
                color: foreground,
                onPressed: null,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          _actionSlot(
            _miniButton(
              label: mounted ? '卸载' : '挂载',
              icon: mounted ? LucideIcons.x : LucideIcons.link,
              color: foreground,
              onPressed: primaryAction == null
                  ? null
                  : () => primaryAction(bucket),
            ),
          ),
          const SizedBox(width: 6),
          _actionSlot(
            _BucketOverflowMenuButton(
              items: moreMenuItems,
              color: foreground,
              label: '更多',
              enabled: moreMenuItems.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionSlot(Widget child) {
    return SizedBox(
      width: _actionButtonWidth,
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  Widget _miniButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _BucketOverflowMenuButton extends StatefulWidget {
  const _BucketOverflowMenuButton({
    required this.items,
    required this.color,
    required this.label,
    required this.enabled,
  });

  final List<Widget> items;
  final Color color;
  final String label;
  final bool enabled;

  @override
  State<_BucketOverflowMenuButton> createState() =>
      _BucketOverflowMenuButtonState();
}

class _BucketOverflowMenuButtonState extends State<_BucketOverflowMenuButton> {
  final GlobalKey _buttonKey = GlobalKey();
  late final ShadContextMenuController _controller;
  Offset? _menuAnchorOffset;

  @override
  void initState() {
    super.initState();
    _controller = ShadContextMenuController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMenu() {
    final buttonContext = _buttonKey.currentContext;
    if (!mounted ||
        buttonContext == null ||
        !widget.enabled ||
        widget.items.isEmpty) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    setState(() {
      _menuAnchorOffset = topLeft + Offset(0, box.size.height + 4);
    });
    _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    return ShadContextMenu(
      anchor: _menuAnchorOffset == null
          ? null
          : ShadGlobalAnchor(_menuAnchorOffset!),
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 164),
      effects: const [],
      popoverReverseDuration: Duration.zero,
      items: widget.items,
      child: KeyedSubtree(
        key: _buttonKey,
        child: ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: widget.enabled ? _showMenu : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.ellipsisVertical, size: 13, color: widget.color),
              const SizedBox(width: 4),
              Text(widget.label, style: const TextStyle(fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}
