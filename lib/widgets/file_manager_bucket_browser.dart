// Bucket browser keeps the bucket-only list/grid rendering out of the page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerBucketBrowser extends StatelessWidget {
  const FileManagerBucketBrowser({
    super.key,
    required this.buckets,
    required this.isGrid,
    required this.gridIconSize,
    required this.listIconSize,
    required this.onOpenBucket,
    required this.mountStatuses,
    required this.busyBuckets,
    this.onMountBucket,
    this.onUnmountBucket,
    this.onOpenMountedBucket,
  });

  final List<BucketInfo> buckets;
  final bool isGrid;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<String> onOpenBucket;
  final Map<String, BucketMountStatus> mountStatuses;
  final Set<String> busyBuckets;
  final ValueChanged<String>? onMountBucket;
  final ValueChanged<String>? onUnmountBucket;
  final ValueChanged<String>? onOpenMountedBucket;

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return _buildGrid();
    }
    return _buildList();
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
                (bucket) => FileGridItem(
                  leading: WhiteSurFileIcon(
                    assetPath:
                        'assets/icons/whitesur/places/network-server.svg',
                    size: gridIconSize,
                  ),
                  title: bucket.name,
                  subtitle: '存储桶',
                  onTap: () => onOpenBucket(bucket.name),
                  footer: _BucketMountActions(
                    bucket: bucket.name,
                    status: mountStatuses[bucket.name],
                    busy: busyBuckets.contains(bucket.name),
                    onMountBucket: onMountBucket,
                    onUnmountBucket: onUnmountBucket,
                    onOpenMountedBucket: onOpenMountedBucket,
                    compact: true,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildList() {
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: ListView.builder(
        itemCount: buckets.length,
        itemBuilder: (context, index) {
          final bucket = buckets[index];
          return FileListTile(
            leading: WhiteSurFileIcon(
              assetPath: 'assets/icons/whitesur/places/network-server.svg',
              size: listIconSize,
            ),
            title: bucket.name,
            modifiedLabel: '存储桶',
            onTap: () => onOpenBucket(bucket.name),
            showDivider: index != buckets.length - 1,
            trailing: SizedBox(
              width: 224,
              child: Align(
                alignment: Alignment.centerRight,
                child: _BucketMountActions(
                  bucket: bucket.name,
                  status: mountStatuses[bucket.name],
                  busy: busyBuckets.contains(bucket.name),
                  onMountBucket: onMountBucket,
                  onUnmountBucket: onUnmountBucket,
                  onOpenMountedBucket: onOpenMountedBucket,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BucketMountActions extends StatelessWidget {
  const _BucketMountActions({
    required this.bucket,
    required this.status,
    required this.busy,
    required this.onMountBucket,
    required this.onUnmountBucket,
    required this.onOpenMountedBucket,
    this.compact = false,
  });

  final String bucket;
  final BucketMountStatus? status;
  final bool busy;
  final ValueChanged<String>? onMountBucket;
  final ValueChanged<String>? onUnmountBucket;
  final ValueChanged<String>? onOpenMountedBucket;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mounted = status?.mounted ?? false;
    final foreground = theme.colorScheme.primary;

    if (busy) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compact ? 10 : 12,
            height: compact ? 10 : 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: foreground,
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Text(
            '处理中',
            style: TextStyle(
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        _miniButton(
          label: mounted ? '已挂载' : '挂载',
          icon: mounted ? LucideIcons.hardDriveDownload : LucideIcons.link,
          color: foreground,
          onPressed: mounted || onMountBucket == null
              ? null
              : () => onMountBucket!(bucket),
        ),
        if (mounted) ...[
          _miniButton(
            label: '打开',
            icon: LucideIcons.folderOpen,
            color: foreground,
            onPressed: onOpenMountedBucket == null
                ? null
                : () => onOpenMountedBucket!(bucket),
          ),
          _miniButton(
            label: '卸载',
            icon: LucideIcons.x,
            color: theme.colorScheme.mutedForeground,
            onPressed: onUnmountBucket == null
                ? null
                : () => onUnmountBucket!(bucket),
          ),
        ],
      ],
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
          Icon(icon, size: compact ? 12 : 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: compact ? 10.5 : 11.5)),
        ],
      ),
    );
  }
}
