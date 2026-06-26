part of 'file_sync_tasks_page.dart';

// 文件同步任务页的配置管理动作：新增、编辑、删除、启停、立即同步。
// 与设置页解耦——这里是同步配置的唯一 CRUD 入口。
extension _FileSyncTasksActions on _FileSyncTasksPageState {
  // 加载所有账号下的桶列表，供编辑器选择目标桶。逻辑与文件管理页一致。
    Future<void> _loadBuckets() async {
      markDirty(() => _loadingBuckets = true);
      try {
        final entries = <FileManagerBucketEntry>[];
        final sources = <_BucketSource>[];
        if (widget.profiles.isEmpty) {
          sources.add(_BucketSource(
            profileName: 'default',
            sourceLabel: _sourceLabel(widget.config),
            config: widget.config,
          ));
        } else {
          for (final profile in widget.profiles) {
            final config = await widget.api.loadProfile(profile.name);
            sources.add(_BucketSource(
              profileName: profile.name,
              sourceLabel: _sourceLabel(config),
              config: config,
            ));
          }
        }
        for (final source in sources) {
          final buckets = await widget.api.listBuckets(source.config);
          for (final bucket in buckets) {
            entries.add(FileManagerBucketEntry.fromBucketInfo(
              bucket: bucket,
              profileName: source.profileName,
              sourceLabel: source.sourceLabel,
              config: source.config,
            ));
          }
        }
        entries.sort((a, b) {
          final sc = a.sourceLabel.compareTo(b.sourceLabel);
          return sc != 0 ? sc : a.bucket.name.compareTo(b.bucket.name);
        });
        if (mounted) markDirty(() => _buckets = entries);
      } catch (_) {
        // 桶列表加载失败时静默，编辑器会显示空桶提示。
      } finally {
        if (mounted) markDirty(() => _loadingBuckets = false);
      }
    }

  String _sourceLabel(dynamic config) {
      if (config is! RemoteStorageConfig) return '账号';
      final name = config.displayName.trim().isNotEmpty
          ? config.displayName.trim()
          : config.accessKeyId.trim();
      final label = name.isEmpty ? '账号' : name;
      return '$label · ${config.storageType.label}';
    }

  Future<void> _addProfile() async {
    await showShadDialog(
      context: context,
      builder: (_) => FileSyncProfileEditor(
        buckets: _buckets,
        onSave: _saveProfile,
      ),
    );
  }

  Future<void> _editProfile(SyncProfileRuntime runtime) async {
    await showShadDialog(
      context: context,
      builder: (_) => FileSyncProfileEditor(
        buckets: _buckets,
        initial: runtime.profile,
        onSave: _saveProfile,
      ),
    );
  }

  Future<bool> _saveProfile(SyncProfile profile) async {
    try {
      await SyncProfileNotifier.instance.saveProfile(profile);
      return true;
    } catch (e) {
      if (!mounted) return false;
      showAppErrorToast(context, message: '保存失败：$e');
      return false;
    }
  }

  Future<void> _deleteProfile(SyncProfileRuntime runtime) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (_) => ShadDialog(
        title: const Text('删除同步配置'),
        description: Text('确定要删除「${runtime.profile.name}」吗？'),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            const SizedBox(width: 10),
            ShadButton.destructive(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await SyncProfileNotifier.instance.deleteProfile(runtime.profile.id);
      if (!mounted) return;
      showAppToast(context, message: '已删除');
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '删除失败：$e');
    }
  }

  Future<void> _toggleEnabled(SyncProfileRuntime runtime, bool value) async {
    try {
      await SyncProfileNotifier.instance.saveProfile(
        runtime.profile.copyWith(enabled: value),
      );
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '操作失败：$e');
    }
  }

  Future<void> _triggerSync(SyncProfileRuntime runtime) async {
    try {
      final ops =
          await SyncProfileNotifier.instance.triggerProfile(runtime.profile.id);
      if (!mounted) return;
      showAppToast(context, message: ops > 0 ? '已触发同步，共 $ops 个操作' : '已是最新，无待同步项');
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '同步失败：$e');
    }
  }
}

/// 桶来源的内部辅助结构。
class _BucketSource {
  const _BucketSource({
    required this.profileName,
    required this.sourceLabel,
    required this.config,
  });

  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
}
