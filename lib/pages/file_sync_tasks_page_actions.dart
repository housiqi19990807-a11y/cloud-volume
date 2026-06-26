part of 'file_sync_tasks_page.dart';

// 文件同步任务页的配置管理动作：新增、编辑、删除、启停、立即同步。
// 与设置页解耦——这里是同步配置的唯一 CRUD 入口。
extension _FileSyncTasksActions on _FileSyncTasksPageState {
  Future<void> _addProfile() async {
    await showShadDialog(
      context: context,
      builder: (_) => FileSyncProfileEditor(
        profiles: widget.profiles,
        onSave: _saveProfile,
      ),
    );
  }

  Future<void> _editProfile(SyncProfileRuntime runtime) async {
    await showShadDialog(
      context: context,
      builder: (_) => FileSyncProfileEditor(
        profiles: widget.profiles,
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
