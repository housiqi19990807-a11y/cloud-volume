// Configuration backup settings manage a hidden remote target and its encrypted snapshots.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsConfigBackupSection extends StatefulWidget {
  const SettingsConfigBackupSection({
    super.key,
    required this.theme,
    required this.api,
    required this.profiles,
    required this.onRestored,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final List<ProfileInfo> profiles;
  final ValueChanged<BootstrapState> onRestored;

  @override
  State<SettingsConfigBackupSection> createState() =>
      _SettingsConfigBackupSectionState();
}

class _SettingsConfigBackupSectionState
    extends State<SettingsConfigBackupSection> {
  late final TextEditingController _bucketController;
  late final TextEditingController _prefixController;
  ConfigBackupSettings _settings = const ConfigBackupSettings();
  List<ConfigBackupSnapshot> _snapshots = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bucketController = TextEditingController();
    _prefixController = TextEditingController(
      text: 'cloud-volume-config-backups',
    );
    _load();
  }

  @override
  void dispose() {
    _bucketController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.api.loadConfigBackupSettings();
      if (!mounted) return;
      _bucketController.text = settings.target.bucket;
      _prefixController.text = settings.target.prefix;
      setState(() => _settings = settings);
      await _refreshSnapshots();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ConfigBackupSettings get _draft => _settings.copyWith(
    target: _settings.target.copyWith(
      bucket: _bucketController.text.trim(),
      prefix: _prefixController.text.trim(),
    ),
  );

  Future<void> _save({bool? enabled}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveConfigBackupSettings(
        _draft.copyWith(enabled: enabled),
      );
      if (!mounted) return;
      setState(() => _settings = saved);
      await _refreshSnapshots();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshSnapshots() async {
    try {
      final items = await widget.api.listConfigBackups();
      if (mounted) setState(() => _snapshots = items);
    } catch (_) {
      // A target can be partly configured while the user is still choosing it.
    }
  }

  Future<void> _backupNow() async {
    await _save();
    if (!mounted || _error != null) return;
    setState(() => _saving = true);
    try {
      await widget.api.backupConfigNow();
      await _refreshSnapshots();
      if (mounted) showAppToast(context, title: '配置已备份', message: '已加密保存到指定存储');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restore(ConfigBackupSnapshot snapshot) async {
    final confirmed = await showAppConfirmModal(
      context: context,
      title: const Text('还原此配置备份？'),
      description: const Text('当前账号、代理和显示排序将被替换；备份目标会保留，方便继续还原。'),
      confirmLabel: '还原配置',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final state = await widget.api.restoreConfigBackup(snapshot.key);
      if (!mounted) return;
      widget.onRestored(state);
      showAppToast(context, title: '配置已还原', message: snapshot.displayName);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _configureStandalone() async {
    await showAppModal<void>(
      context: context,
      builder: (_) => CloudStorageAccountDialog(
        api: widget.api,
        initialConfig: _settings.target.standalone,
        editing: _settings.target.standalone != null,
        onListBuckets: widget.api.listBuckets,
        onStartBaiduPanAuthorization: widget.api.startBaiduPanAuthorization,
        onAuthorizeBaiduPan: widget.api.authorizeBaiduPan,
        onSave: (config) async {
          if (!config.isConfigured) return false;
          if (!mounted) return false;
          setState(() {
            _settings = _settings.copyWith(
              target: _settings.target.copyWith(
                profileName: '',
                standalone: config,
              ),
            );
            if (_bucketController.text.trim().isEmpty) {
              _bucketController.text = config.bucket;
            }
          });
          return true;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final profiles = widget.profiles;
    final target = _settings.target;
    final selectorValue = target.profileName.isEmpty
        ? '__standalone__'
        : target.profileName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '将账号配置加密保存到一个远端存储。可复用已有账号，也可单独配置一个不会显示在账号列表中的备份连接。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                '配置变更后自动备份',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.foreground,
                ),
              ),
            ),
            ShadSwitch(
              value: _settings.enabled,
              onChanged: _saving ? null : (value) => _save(enabled: value),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '备份存储',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 6),
        ShadSelect<String>(
          key: ValueKey<String>(selectorValue),
          initialValue: selectorValue,
          minWidth: 260,
          selectedOptionBuilder: (context, selected) => Text(selected),
          options: [
            ...profiles.map(
              (profile) => ShadOption(
                value: profile.name,
                child: Text(
                  profile.displayName.isEmpty
                      ? profile.name
                      : profile.displayName,
                ),
              ),
            ),
            const ShadOption(
              value: '__standalone__',
              child: Text('独立备份存储（不显示在账号中）'),
            ),
          ],
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(
                    () => _settings = _settings.copyWith(
                      target: target.copyWith(
                        profileName: value == '__standalone__' ? '' : value,
                      ),
                    ),
                  );
                },
        ),
        if (target.profileName.isEmpty) ...[
          const SizedBox(height: 10),
          ShadButton.outline(
            onPressed: _saving ? null : _configureStandalone,
            child: Text(target.standalone == null ? '配置独立存储' : '编辑独立存储'),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ShadInput(
                controller: _bucketController,
                enabled: !_saving,
                placeholder: const Text('备份存储桶 / 根目录'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ShadInput(
                controller: _prefixController,
                enabled: !_saving,
                placeholder: const Text('备份目录'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              onPressed: _saving ? null : _save,
              child: const Text('保存目标'),
            ),
            ShadButton(
              onPressed: _saving || _loading ? null : _backupNow,
              child: Text(_saving ? '处理中…' : '立即备份'),
            ),
            ShadButton.ghost(
              onPressed: _saving ? null : _refreshSnapshots,
              child: const Text('刷新列表'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '配置备份列表',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _snapshots.isEmpty)
          Text(
            '还没有可用备份。',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ..._snapshots.map(
          (snapshot) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    snapshot.createdAt.isEmpty
                        ? snapshot.displayName
                        : snapshot.createdAt,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _saving ? null : () => _restore(snapshot),
                  child: const Text('还原'),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.destructive,
              ),
            ),
          ),
      ],
    );
  }
}
