// 文件对象区：负责列表/网格渲染、非根目录的 ".." 返回项，以及对象交互分发。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
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
    required this.onOpenFile,
    required this.onDownloadFile,
    required this.onNavigateUp,
    required this.onObjectAction,
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
  final ValueChanged<ObjectInfo> onOpenFile;
  final ValueChanged<ObjectInfo> onDownloadFile;
  final VoidCallback onNavigateUp;
  final void Function(ObjectInfo object, FileObjectAction action)
  onObjectAction;

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
                (object) => _wrapWithContextMenu(
                  object,
                  FileGridItem(
                    leading: _leading(object, theme, gridIconSize),
                    title: _title(object),
                    subtitle: _subtitle(object, forGrid: true),
                    onTap: _tapHandler(object),
                  ),
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
      child: Column(
        children: [
          _ListHeader(theme: theme),
          Expanded(
            child: ListView.builder(
              itemCount: objects.length,
              itemBuilder: (context, index) {
                final object = objects[index];
                return _wrapWithContextMenu(
                  object,
                  FileListTile(
                    leading: _leading(object, theme, listIconSize),
                    title: _title(object),
                    sizeLabel: _sizeLabel(object),
                    modifiedLabel: _modifiedLabel(object),
                    onTap: _tapHandler(object),
                    showDivider: index != objects.length - 1,
                  ),
                );
              },
            ),
          ),
        ],
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

  String _sizeLabel(ObjectInfo object) {
    if (_isParentDirectory(object) || object.isDir) return '';
    return object.sizeText;
  }

  String _modifiedLabel(ObjectInfo object) {
    if (_isParentDirectory(object) || object.lastModified.isEmpty) return '';
    return object.lastModified;
  }

  VoidCallback _tapHandler(ObjectInfo object) {
    if (_isParentDirectory(object)) return onNavigateUp;
    if (object.isDir) return () => onOpenDirectory(object.key);
    return () => onOpenFile(object);
  }

  Widget _wrapWithContextMenu(ObjectInfo object, Widget child) {
    if (_isParentDirectory(object)) {
      return child;
    }
    return ShadContextMenuRegion(
      tapEnabled: false,
      longPressEnabled: false,
      items: buildObjectActionMenuItems(
        object: object,
        onOpen: () => _tapHandler(object)(),
        onDownload: object.isDir ? null : () => onDownloadFile(object),
        onRename: () => onObjectAction(object, FileObjectAction.rename),
        onDelete: () => onObjectAction(object, FileObjectAction.delete),
      ),
      child: child,
    );
  }

  bool _isParentDirectory(ObjectInfo object) {
    return object.key == _parentDirectoryEntry.key;
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.7);
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('名称', style: labelStyle)),
          const SizedBox(width: 12),
          SizedBox(
            width: FileListTile.sizeColumnWidth,
            child: Text('大小', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: FileListTile.modifiedColumnWidth,
            child: Text('修改时间', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}
