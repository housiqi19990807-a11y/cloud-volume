// Bucket browser keeps the bucket-only list/grid rendering out of the page file.

import 'package:flutter/material.dart';
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
  });

  final List<BucketInfo> buckets;
  final bool isGrid;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<String> onOpenBucket;

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
          );
        },
      ),
    );
  }
}
