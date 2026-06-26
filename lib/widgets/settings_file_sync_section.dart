// 文件同步设置区块：在系统设置页"文件同步"子 Tab 中展示所有同步配置，
// 支持新增、编辑、删除、启停和立即同步。状态实时反映 Go 侧调度器。
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/file_sync_profile_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsFileSyncSection extends StatefulWidget {
  const SettingsFileSyncSection({
    super.key,
    required this.theme,
    required this.notifier,
    required this.profiles,
  });

  final ShadThemeData theme;
  final SyncProfileNotifier notifier;
  final List<ProfileInfo> profiles;

  @override
  State<SettingsFileSyncSection> createState() =>
      _SettingsFileSyncSectionState();
}

class _SettingsFileSyncSectionState extends State<SettingsFileSyncSection> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

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
      await widget.notifier.saveProfile(profile);
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
      await widget.notifier.deleteProfile(runtime.profile.id);
      if (!mounted) return;
      showAppToast(context, message: '已删除');
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '删除失败：$e');
    }
  }

  Future<void> _toggleEnabled(SyncProfileRuntime runtime, bool value) async {
    try {
      await widget.notifier.saveProfile(
        runtime.profile.copyWith(enabled: value),
      );
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '操作失败：$e');
    }
  }

  Future<void> _triggerSync(SyncProfileRuntime runtime) async {
    try {
      final ops = await widget.notifier.triggerProfile(runtime.profile.id);
      if (!mounted) return;
      showAppToast(context, message: ops > 0 ? '已触发同步，共 $ops 个操作' : '已是最新，无待同步项');
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '同步失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final profiles = widget.notifier.profiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '将本地目录定期同步到远端桶目录，支持双向同步与冲突策略。'
          '正在编辑的文件会等到静默后才同步，避免频繁操作远端。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '同步配置（${profiles.length}）',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.foreground,
              ),
            ),
            ShadButton(
              onPressed: _addProfile,
              child: const Text('新建配置'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (profiles.isEmpty)
          _emptyState(theme)
        else
          ...profiles.map((p) => _profileCard(theme, p)),
      ],
    );
  }

  Widget _emptyState(ShadThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(
            LucideIcons.refreshCw,
            size: 32,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有同步配置',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(ShadThemeData theme, SyncProfileRuntime runtime) {
    final profile = runtime.profile;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ),
              _statusBadge(theme, runtime.status),
            ],
          ),
          const SizedBox(height: 8),
          _metaRow(theme, LucideIcons.folder, profile.localPath),
          const SizedBox(height: 4),
          _metaRow(
            theme,
            LucideIcons.cloudUpload,
            '${profile.bucket}/${profile.remotePrefix.isEmpty ? '' : profile.remotePrefix}',
          ),
          const SizedBox(height: 4),
          _metaRow(theme, LucideIcons.arrowLeftRight, profile.direction.label),
          if (runtime.lastSyncAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            _metaRow(
              theme,
              LucideIcons.clock,
              '上次同步：${runtime.lastSyncAt}',
            ),
          ],
          if (runtime.lastError.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              runtime.lastError,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              ShadSwitch(
                value: profile.enabled,
                onChanged: (v) => _toggleEnabled(runtime, v),
              ),
              const SizedBox(width: 4),
              Text(
                profile.enabled ? '已启用' : '已暂停',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
              const Spacer(),
              ShadButton.outline(
                onPressed: () => _triggerSync(runtime),
                child: const Text('立即同步'),
              ),
              const SizedBox(width: 8),
              ShadButton.outline(
                onPressed: () => _editProfile(runtime),
                child: const Text('编辑'),
              ),
              const SizedBox(width: 8),
              ShadButton.destructive(
                onPressed: () => _deleteProfile(runtime),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaRow(ShadThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.mutedForeground),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(ShadThemeData theme, SyncProfileStatus status) {
    final (color, _) = _statusColor(theme, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  (Color, bool) _statusColor(
    ShadThemeData theme,
    SyncProfileStatus status,
  ) {
    switch (status) {
      case SyncProfileStatus.syncing:
        return (theme.colorScheme.primary, true);
      case SyncProfileStatus.error:
        return (theme.colorScheme.destructive, false);
      case SyncProfileStatus.paused:
        return (theme.colorScheme.mutedForeground, false);
      case SyncProfileStatus.idle:
        return (theme.colorScheme.primary, false);
    }
  }
}
