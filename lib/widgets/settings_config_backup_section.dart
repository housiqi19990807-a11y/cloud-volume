// Settings card for encrypted remote configuration backups.
// Target setup stays on the page; snapshot history opens in a modal so a long
// list does not bloat the settings scroll view.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_history_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _kStandaloneTargetValue = '__standalone__';

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
  bool _backingUp = false;
  bool _listing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bucketController = TextEditingController();
    _prefixController = TextEditingController(
      text: 'cloud-volume-config-backups',
    );
    _bucketController.addListener(_onDraftChanged);
    _prefixController.addListener(_onDraftChanged);
    _load();
  }

  @override
  void dispose() {
    _bucketController
      ..removeListener(_onDraftChanged)
      ..dispose();
    _prefixController
      ..removeListener(_onDraftChanged)
      ..dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _busy => _saving || _backingUp || _listing;

  bool get _isDirty {
    final target = _settings.target;
    return _bucketController.text.trim() != target.bucket ||
        _prefixController.text.trim() != target.prefix;
  }

  ConfigBackupSettings get _draft => _settings.copyWith(
    target: _settings.target.copyWith(
      bucket: _bucketController.text.trim(),
      prefix: _prefixController.text.trim(),
    ),
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.loadConfigBackupSettings();
      if (!mounted) return;
      _bucketController.text = settings.target.bucket;
      _prefixController.text = settings.target.prefix;
      setState(() => _settings = settings);
      await _refreshSnapshots(quiet: true);
    } catch (error) {
      if (mounted) setState(() => _error = configBackupFriendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save({bool? enabled, bool quiet = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveConfigBackupSettings(
        _draft.copyWith(enabled: enabled),
      );
      if (!mounted) return false;
      setState(() => _settings = saved);
if (!quiet) {
        showAppToast(context, message: '备份目标已保存');
      }
      await _refreshSnapshots(quiet: true);
      return true;
    } catch (error) {
      if (mounted) {
        final message = configBackupFriendlyError(error);
        setState(() => _error = message);
        showAppToast(context, title: '保存失败', message: message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshSnapshots({bool quiet = false}) async {
    setState(() {
      _listing = true;
      if (!quiet) _error = null;
    });
    try {
      final items = await widget.api.listConfigBackups();
      if (mounted) setState(() => _snapshots = items);
    } catch (error) {
      // Partial targets are common while the user is still choosing storage.
      if (!quiet && mounted) {
        setState(() => _error = configBackupFriendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _listing = false);
    }
  }

  Future<void> _backupNow() async {
    final saved = await _save(quiet: true);
    if (!mounted || !saved) return;
    setState(() {
      _backingUp = true;
      _error = null;
    });
    try {
      await widget.api.backupConfigNow();
      await _refreshSnapshots(quiet: true);
      if (mounted) {
        showAppToast(context, title: '配置已备份', message: '已加密保存到指定存储');
      }
    } catch (error) {
      if (mounted) {
        final message = configBackupFriendlyError(error);
        setState(() => _error = message);
        showAppToast(context, title: '备份失败', message: message);
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _restore(ConfigBackupSnapshot snapshot) async {
    final label = configBackupSnapshotPrimaryLabel(snapshot);
    final confirmed = await showAppConfirmModal(
      context: context,
      title: const Text('还原此配置备份？'),
      description: Text(
        '将用 $label 替换当前账号、代理和显示排序；备份目标会保留，方便继续管理备份。',
      ),
      confirmLabel: '还原配置',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = await widget.api.restoreConfigBackup(snapshot.key);
      if (!mounted) return;
      widget.onRestored(state);
      showAppToast(context, title: '配置已还原', message: label);
    } catch (error) {
      if (mounted) {
        final message = configBackupFriendlyError(error);
        setState(() => _error = message);
        showAppToast(context, title: '还原失败', message: message);
      }
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

  Future<void> _openHistoryDialog() async {
    if (!mounted) return;
    await showAppModal<void>(
      context: context,
      builder: (dialogContext) => ConfigBackupHistoryDialog(
        api: widget.api,
        initialSnapshots: _snapshots,
        onRestore: (snapshot) async {
          Navigator.of(dialogContext).pop();
          await _restore(snapshot);
        },
        onSnapshotsChanged: (items) {
          if (!mounted) return;
          setState(() => _snapshots = items);
        },
      ),
    );
  }

  String _profileLabel(ProfileInfo profile) {
    final name = profile.displayName.trim().isEmpty
        ? profile.name
        : profile.displayName.trim();
    return '$name · ${profile.storageType.label}';
  }

  String _selectorLabel(String value) {
    if (value == _kStandaloneTargetValue) {
      return '独立备份存储（不显示在账号中）';
    }
    for (final profile in widget.profiles) {
      if (profile.name == value) return _profileLabel(profile);
    }
    return value;
  }

  String _targetStatusText() {
    final target = _settings.target;
    if (target.profileName.isNotEmpty) {
      ProfileInfo? profile;
      for (final item in widget.profiles) {
        if (item.name == target.profileName) {
          profile = item;
          break;
        }
      }
      if (profile == null) {
        return '已选择账号「${target.profileName}」，但当前账号列表中找不到它。';
      }
      final endpoint = profile.endpoint.trim();
      return endpoint.isEmpty
          ? '使用账号「${_profileLabel(profile)}」作为备份目标。'
          : '使用账号「${_profileLabel(profile)}」· $endpoint';
    }

    final standalone = target.standalone;
    if (standalone == null || !standalone.isConfigured) {
      return '尚未配置独立备份存储。请先完成连接信息，再保存目标。';
    }
    final name = standalone.displayName.trim().isEmpty
        ? standalone.storageType.label
        : standalone.displayName.trim();
    final endpoint = standalone.endpoint.trim();
    return endpoint.isEmpty
        ? '独立备份存储已配置：$name'
        : '独立备份存储已配置：$name · $endpoint';
  }

  String _historySummary() {
    if (_loading || _listing) return '正在读取远端备份…';
    if (_snapshots.isEmpty) return '还没有远端备份，可先保存目标后立即备份一次。';
    final latest = configBackupSnapshotPrimaryLabel(_snapshots.first);
    return '已有 ${_snapshots.length} 份备份，最近一份：$latest';
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final target = _settings.target;
    final selectorValue = target.profileName.isEmpty
        ? _kStandaloneTargetValue
        : target.profileName;
    final canBackup =
        !_busy &&
        !_loading &&
        (_draft.target.profileName.isNotEmpty ||
            (_draft.target.standalone?.isConfigured ?? false)) &&
        _draft.target.bucket.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '将账号、代理和显示排序加密保存到远端存储。可复用已有账号，也可单独配置一个不会出现在账号列表中的备份连接。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 16),
        _SectionHeader(
          theme: theme,
          title: '自动备份',
          description: '账号、代理或排序变更后，会在短延迟后自动写入远端备份。',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '配置变更后自动备份',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.foreground,
                ),
              ),
            ),
            ShadSwitch(
              value: _settings.enabled,
              onChanged: _busy ? null : (value) => _save(enabled: value),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          theme: theme,
          title: '备份目标',
          description: '选择存放加密配置快照的远端存储、存储桶和目录。',
        ),
        const SizedBox(height: 10),
        Text(
          '备份存储来源',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 6),
        ShadSelect<String>(
          key: ValueKey<String>(selectorValue),
          initialValue: selectorValue,
          minWidth: 320,
          selectedOptionBuilder: (context, selected) =>
              Text(_selectorLabel(selected)),
          options: [
            ...widget.profiles.map(
              (profile) => ShadOption(
                value: profile.name,
                child: Text(_profileLabel(profile)),
              ),
            ),
            const ShadOption(
              value: _kStandaloneTargetValue,
              child: Text('独立备份存储（不显示在账号中）'),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(
                    () => _settings = _settings.copyWith(
                      target: target.copyWith(
                        profileName: value == _kStandaloneTargetValue
                            ? ''
                            : value,
                      ),
                    ),
                  );
                },
        ),
        const SizedBox(height: 10),
        _InfoBlock(theme: theme, text: _targetStatusText()),
        if (target.profileName.isEmpty) ...[
          const SizedBox(height: 10),
          ShadButton.outline(
            onPressed: _busy ? null : _configureStandalone,
            child: Text(
              target.standalone == null || !target.standalone!.isConfigured
                  ? '配置独立存储'
                  : '编辑独立存储',
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LabeledField(
                theme: theme,
                label: '存储桶 / 根目录',
                child: ShadInput(
                  controller: _bucketController,
                  enabled: !_busy,
                  placeholder: const Text('例如 my-bucket'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LabeledField(
                theme: theme,
                label: '备份目录',
                child: ShadInput(
                  controller: _prefixController,
                  enabled: !_busy,
                  placeholder: const Text('cloud-volume-config-backups'),
                ),
              ),
            ),
          ],
        ),
        if (_isDirty) ...[
          const SizedBox(height: 8),
          Text(
            '目标路径已修改，保存目标或立即备份时会一并写入。',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ShadButton(
              onPressed: canBackup ? _backupNow : null,
              child: Text(_backingUp ? '备份中…' : '立即备份'),
            ),
            ShadButton.outline(
              onPressed: _busy ? null : () => _save(),
              child: Text(_saving && !_backingUp ? '保存中…' : '保存目标'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionHeader(
          theme: theme,
          title: '备份历史',
          description: '远端快照可能较多，点击后在拟态框中查看并还原。',
        ),
        const SizedBox(height: 10),
        _InfoBlock(theme: theme, text: _historySummary()),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              onPressed: _busy || _loading ? null : _openHistoryDialog,
              child: Text(
                _snapshots.isEmpty
                    ? '查看备份历史'
                    : '查看备份历史（${_snapshots.length}）',
              ),
            ),
            ShadButton.ghost(
              onPressed: _busy ? null : () => _refreshSnapshots(),
              child: Text(_listing ? '刷新中…' : '刷新'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.title,
    required this.description,
  });

  final ShadThemeData theme;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.theme,
    required this.label,
    required this.child,
  });

  final ShadThemeData theme;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.theme, required this.text});

  final ShadThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: theme.colorScheme.foreground,
        ),
      ),
    );
  }
}
