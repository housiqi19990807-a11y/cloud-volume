part of 'remote_directory_picker_dialog.dart';

// 远程目录选择器的数据加载与创建目录动作。

extension _RemoteDirectoryPickerActions on _RemoteDirectoryPickerDialogState {
  Future<void> _loadObjects() async {
    if (_activeBucket == null) return;
    markDirty(() => _loading = true);
    try {
      final objects = await widget.api.listObjects(
        _activeBucket!.config,
        _activeBucket!.bucket.name,
        _prefix,
      );
      if (mounted) markDirty(() => _objects = objects);
    } catch (e) {
      if (mounted) markDirty(() => _error = '加载失败：$e');
    } finally {
      if (mounted) markDirty(() => _loading = false);
    }
  }

  Future<void> _createDirectory() async {
    final name = _dirNameController.text.trim();
    if (name.isEmpty || _activeBucket == null) return;
    try {
      await widget.api.createDirectory(
        _activeBucket!.config,
        _activeBucket!.bucket.name,
        _prefix,
        name,
      );
      if (!mounted) return;
      markDirty(() => _showCreateDir = false);
      _dirNameController.clear();
      showAppToast(context, message: '目录已创建');
      await _loadObjects();
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '创建失败：$e');
    }
  }

  /// 创建目录的内联输入行，展开时显示在内容区上方。
  Widget buildCreateDirInput(ShadThemeData theme) {
    if (!_showCreateDir) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: _dirNameController,
              placeholder: const Text('输入目录名称'),
              autofocus: true,
              onSubmitted: (_) => _createDirectory(),
            ),
          ),
          const SizedBox(width: 8),
          ShadButton(
            onPressed: _createDirectory,
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}
