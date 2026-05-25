// 文件对象区：负责列表/网格渲染、非根目录的 ".." 返回项，以及对象交互分发。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:remote_storage/widgets/file_manager_object_header.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _objectContextMenuGroup = 'file_manager_object_browser';

class FileManagerObjectBrowser extends StatelessWidget {
  const FileManagerObjectBrowser({
    super.key,
    required this.objects,
    required this.prefix,
    required this.isGrid,
    required this.fileOpenMode,
    required this.selectedKeys,
    required this.gridIconSize,
    required this.listIconSize,
    required this.onOpenDirectory,
    required this.onOpenFile,
    required this.onDownloadFile,
    required this.onNavigateUp,
    required this.onToggleSelection,
    required this.onToggleSelectAll,
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
  final FileOpenMode fileOpenMode;
  final Set<String> selectedKeys;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<String> onOpenDirectory;
  final ValueChanged<ObjectInfo> onOpenFile;
  final ValueChanged<ObjectInfo> onDownloadFile;
  final VoidCallback onNavigateUp;
  final ValueChanged<ObjectInfo> onToggleSelection;
  final VoidCallback onToggleSelectAll;
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
                    onDoubleTap: _doubleTapHandler(object),
                    onTitleTap: _titleTapHandler(object),
                    onSelectionTap: _selectionTapHandler(object),
                    isSelected: _isSelected(object),
                    showSelectionControl: _showsSelectionControl(object),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildList(List<ObjectInfo> objects, ShadThemeData theme) {
    final selectableObjects = objects.where(
      (object) => !_isParentDirectory(object),
    );
    final selectedCount = selectableObjects
        .where((object) => selectedKeys.contains(object.key))
        .length;
    final totalCount = selectableObjects.length;

    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          FileManagerObjectHeader(
            theme: theme,
            showSelectionControl: fileOpenMode == FileOpenMode.doubleClick,
            allSelected: totalCount > 0 && selectedCount == totalCount,
            partiallySelected: selectedCount > 0 && selectedCount < totalCount,
            onToggleSelectAll: onToggleSelectAll,
          ),
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
                    onDoubleTap: _doubleTapHandler(object),
                    onTitleTap: _titleTapHandler(object),
                    onSelectionTap: _selectionTapHandler(object),
                    isSelected: _isSelected(object),
                    showSelectionControl: _showsSelectionControl(object),
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
    return () {
      if (_dismissActiveContextMenu()) {
        return;
      }
      if (_isSelectionMode) {
        if (_isParentDirectory(object)) {
          return;
        }
        onToggleSelection(object);
        return;
      }
      if (_isParentDirectory(object) ||
          fileOpenMode == FileOpenMode.singleClick) {
        _openObject(object);
        return;
      }
      onToggleSelection(object);
    };
  }

  VoidCallback? _doubleTapHandler(ObjectInfo object) {
    if (_isSelectionMode ||
        _isParentDirectory(object) ||
        fileOpenMode == FileOpenMode.singleClick) {
      return null;
    }
    return () {
      if (_dismissActiveContextMenu()) {
        return;
      }
      _openObject(object);
    };
  }

  VoidCallback _titleTapHandler(ObjectInfo object) {
    return () {
      if (_dismissActiveContextMenu()) {
        return;
      }
      if (_isSelectionMode) {
        if (_isParentDirectory(object)) {
          return;
        }
        onToggleSelection(object);
        return;
      }
      _openObject(object);
    };
  }

  VoidCallback? _selectionTapHandler(ObjectInfo object) {
    if (!_showsSelectionControl(object)) {
      return null;
    }
    return () {
      if (_dismissActiveContextMenu()) {
        return;
      }
      onToggleSelection(object);
    };
  }

  Widget _wrapWithContextMenu(ObjectInfo object, Widget child) {
    if (_isParentDirectory(object)) {
      return child;
    }
    return DesktopContextMenuRegion(
      groupId: _objectContextMenuGroup,
      items: buildObjectActionMenuItems(
        object: object,
        onOpen: () => _runMenuAction(() => _openObject(object)),
        onDownload: object.isDir
            ? null
            : () => _runMenuAction(() => onDownloadFile(object)),
        onCopy: () =>
            _runMenuAction(() => onObjectAction(object, FileObjectAction.copy)),
        onMove: () =>
            _runMenuAction(() => onObjectAction(object, FileObjectAction.move)),
        onRename: () => _runMenuAction(
          () => onObjectAction(object, FileObjectAction.rename),
        ),
        onDelete: () => _runMenuAction(
          () => onObjectAction(object, FileObjectAction.delete),
        ),
      ),
      child: child,
    );
  }

  bool _dismissActiveContextMenu() {
    return DesktopContextMenuRegistry.dismiss(_objectContextMenuGroup);
  }

  void _runMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_objectContextMenuGroup);
    action();
  }

  void _openObject(ObjectInfo object) {
    if (_isParentDirectory(object)) {
      onNavigateUp();
      return;
    }
    if (object.isDir) {
      onOpenDirectory(object.key);
      return;
    }
    onOpenFile(object);
  }

  bool _isSelected(ObjectInfo object) {
    if (_isParentDirectory(object)) {
      return false;
    }
    return selectedKeys.contains(object.key);
  }

  bool _showsSelectionControl(ObjectInfo object) {
    return !_isParentDirectory(object) &&
        fileOpenMode == FileOpenMode.doubleClick;
  }

  bool get _isSelectionMode {
    return fileOpenMode == FileOpenMode.doubleClick && selectedKeys.isNotEmpty;
  }

  bool _isParentDirectory(ObjectInfo object) {
    return object.key == _parentDirectoryEntry.key;
  }
}
