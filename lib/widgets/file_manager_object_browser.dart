// 文件对象区：负责列表/网格渲染、非根目录的 ".." 返回项，以及对象交互分发。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerObjectBrowser extends StatelessWidget {
  const FileManagerObjectBrowser({
    super.key,
    required this.objects,
    required this.prefix,
    required this.isGrid,
    required this.gridIconSize,
    required this.listIconSize,
    required this.onOpenDirectory,
    required this.onDownload,
    required this.onNavigateUp,
  });

  static const ObjectInfo _parentDirectoryEntry = ObjectInfo(
    key: '../',
    size: 0,
    lastModified: '',
    isDir: true,
  );

  final List<ObjectInfo> objects;
  final String prefix;
  final bool isGrid;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<String> onOpenDirectory;
  final ValueChanged<ObjectInfo> onDownload;
  final VoidCallback onNavigateUp;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final visibleObjects = prefix.isEmpty
        ? objects
        : [_parentDirectoryEntry, ...objects];
    if (visibleObjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folderOpen,
              size: 44,
              color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 14),
            Text(
              '此目录为空',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    if (isGrid) return _buildGrid(visibleObjects, theme);
    return _buildList(visibleObjects, theme);
  }

  Widget _buildGrid(List<ObjectInfo> objects, ShadThemeData theme) {
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
          children: objects
              .map(
                (object) => FileGridItem(
                  leading: _leading(object, theme, gridIconSize),
                  title: _title(object),
                  subtitle: _subtitle(object, forGrid: true),
                  onTap: _tapHandler(object),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildList(List<ObjectInfo> objects, ShadThemeData theme) {
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: ListView.builder(
        itemCount: objects.length,
        itemBuilder: (context, index) {
          final object = objects[index];
          return FileListTile(
            leading: _leading(object, theme, listIconSize),
            title: _title(object),
            subtitle: _subtitle(object),
            onTap: _tapHandler(object),
            showDivider: index != objects.length - 1,
          );
        },
      ),
    );
  }

  Widget _leading(ObjectInfo object, ShadThemeData theme, double size) {
    if (_isParentDirectory(object)) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(
            Icons.arrow_upward_rounded,
            size: size * 0.52,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }
    return LocalCloudPanFileIcon(
      name: object.displayName,
      isDirectory: object.isDir,
      size: size,
    );
  }

  String _title(ObjectInfo object) {
    return _isParentDirectory(object) ? '..' : object.displayName;
  }

  String _subtitle(ObjectInfo object, {bool forGrid = false}) {
    if (_isParentDirectory(object)) return '返回上一级';
    if (object.isDir) return forGrid ? '' : '文件夹';
    return forGrid
        ? object.sizeText
        : '${object.sizeText}  ${object.lastModified}';
  }

  VoidCallback _tapHandler(ObjectInfo object) {
    if (_isParentDirectory(object)) return onNavigateUp;
    if (object.isDir) return () => onOpenDirectory(object.key);
    return () => onDownload(object);
  }

  bool _isParentDirectory(ObjectInfo object) {
    return object.key == _parentDirectoryEntry.key;
  }
}
