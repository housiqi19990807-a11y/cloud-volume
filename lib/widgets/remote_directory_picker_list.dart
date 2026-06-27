part of 'remote_directory_picker_dialog.dart';

// 目录浏览列表：目录可进入，文件仅展示（灰色不可点）；可选显示以 . 开头的隐藏文件。

extension _RemoteDirectoryPickerList on _RemoteDirectoryPickerDialogState {
  static const _parentEntry = ObjectInfo(
    key: '../',
    size: 0,
    lastModified: '',
    isDir: true,
  );

  bool _isHiddenFileName(String name) {
    if (name == '..' || name.isEmpty) return false;
    return name.startsWith('.');
  }

  List<ObjectInfo> _directoryListItems() {
    var dirs = _objects.where((o) => o.isDir).toList();
    var files = _objects.where((o) => !o.isDir).toList();
    if (!_showHiddenFiles) {
      dirs = dirs.where((o) => !_isHiddenFileName(o.displayName)).toList();
      files = files.where((o) => !_isHiddenFileName(o.displayName)).toList();
    }
    files.sort((a, b) => a.displayName.compareTo(b.displayName));
    return [
      if (_prefix.isNotEmpty) _parentEntry,
      ...dirs,
      ...files,
    ];
  }

  Widget buildDirectoryList(ShadThemeData theme) {
    final items = _directoryListItems();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folderOpen,
              size: 40,
              color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 10),
            Text(
              '此目录为空',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => _objectEntryTile(theme, items[i]),
    );
  }

  Widget buildHiddenFilesToggle(ShadThemeData theme) {
    if (_activeBucket == null) return const SizedBox.shrink();
    return Row(
      children: [
        Text(
          '显示隐藏文件',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(width: 8),
        ShadSwitch(
          value: _showHiddenFiles,
          onChanged: (v) => markDirty(() => _showHiddenFiles = v),
        ),
      ],
    );
  }

  Widget _objectEntryTile(ShadThemeData theme, ObjectInfo obj) {
    final isParent = obj.key == '../';
    if (isParent) {
      return _dirTile(theme, obj);
    }
    if (obj.isDir) {
      return _dirTile(theme, obj);
    }
    return _fileTile(theme, obj);
  }

  Widget _fileTile(ShadThemeData theme, ObjectInfo obj) {
    final name = obj.displayName;
    final muted = theme.colorScheme.mutedForeground;
    return Opacity(
      opacity: 0.55,
      child: IgnorePointer(
        child: FileListTile(
          leading: ColorFiltered(
            colorFilter: ColorFilter.mode(muted, BlendMode.srcIn),
            child: LocalCloudPanFileIcon(name: name, isDirectory: false, size: 20),
          ),
          title: name,
          sizeLabel: obj.sizeText,
          onTap: () {},
          showDivider: false,
        ),
      ),
    );
  }
}
