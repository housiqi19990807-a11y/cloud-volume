// Settings card for encrypted remote configuration backups.
// Keep the page compact: target setup lives here, long snapshot history opens
// through a clickable summary into a modal list.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_cards.dart';
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

  ConfigBackupSettings get _draft => _settings.copyWith(
    target: _settings.target.copyWith(
      bucket: _bucketController.text.trim(),
      prefix: _prefixController.text.trim(),
    ),
  );

  bool get _isDirty {
    final saved = _settings.target;
    final draft = _draft.target;
    return draft.profileName != saved.profileName ||
        draft.bucket != saved.bucket ||
        draft.prefix != saved.prefix ||
        !_sameStandalone(draft.standalone, saved.standalone);
  }

  bool get _targetReady {
    final target = _draft.target;
    final hasSource = target.profileName.isNotEmpty ||
        (target.standalone?.isConfigured ?? false);
    return hasSource && target.bucket.trim().isNotEmpty;
  }

  bool get _canBackup => !_busy && !_loading && _targetReady;

  bool _sameStandalone(RemoteStorageConfig? a, RemoteStorageConfig? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    return a.toJson().toString() == b.toJson().toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.loadConfigBackupSettings();
      if (!mounted) return;
      _bucketController.text = settings.target.bucket;
      _prefixController.text = settings.target.prefix.isEmpty
          ? 'cloud-volume-config-backups'
          : settings.target.prefix;
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
        showAppErrorToast(context, title: '保存失败', message: message);
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
    if (!_targetReady) {
      setState(() => _error = '请先选择可用的备份存储，并填写存储桶 / 根目录。');
      return;
    }
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
        showAppToast(
          context,
          title: '配置已备份',
          message: '已加密保存到指定存储',
        );
      }
    } catch (error) {
      if (mounted) {
        final message = configBackupFriendlyError(error);
        setState(() => _error = message);
        showAppErrorToast(context, title: '备份失败', message: message);
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
        showAppErrorToast(context, title: '还原失败', message: message);
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

String _selectorLabel(String value) {
    if (value == _kStandaloneTargetValue) {
      return '独立备份存储（不显示在账号中）';
    }
    for (final profile in widget.profiles) {
      if (profile.name == value) return configBackupProfileLabel(profile);
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final target = _settings.target;
    final selectorValue = target.profileName.isEmpty
        ? _kStandaloneTargetValue
        : target.profileName;
    final standaloneConfigured =
        target.standalone != null && target.standalone!.isConfigured;
    final pathPreview = configBackupPathPreview(
      bucket: _bucketController.text,
      prefix: _prefixController.text,
    );
    final historyTitle = configBackupHistoryTitle(
      loading: _loading || _listing,
      snapshots: _snapshots,
    );
    final historyDetail = configBackupHistoryDetail(
      loading: _loading || _listing,
      snapshots: _snapshots,
    );

    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '正在加载配置备份设置…',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '把账号、代理和显示排序加密备份到远端。可复用现有账号，也可单独配置一个不显示在账号列表中的备份连接。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        ConfigBackupSwitchCard(
          theme: theme,
          title: '配置变更后自动备份',
          description: _settings.enabled
              ? '账号、代理或排序变更后，会在短延迟后自动写入远端。'
              : '关闭后仅保留手动备份，不会在配置变更时自动上传。',
          value: _settings.enabled,
          enabled: !_busy,
          onChanged: (value) => _save(enabled: value),
        ),
        const SizedBox(height: 16),
        Text(
          '备份目标',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<String>(
            key: ValueKey<String>(selectorValue),
            initialValue: selectorValue,
            minWidth: 320,
            selectedOptionBuilder: (context, selected) =>
                Text(_selectorLabel(selected)),
            options: [
              ...widget.profiles.map(
                (profile) => ShadOption(
                  value: profile.name,
                  child: Text(configBackupProfileLabel(profile)),
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
        ),
        const SizedBox(height: 10),
        ConfigBackupStatusCard(
          theme: theme,
          title: configBackupTargetStatusTitle(
            target: target,
            profiles: widget.profiles,
          ),
          detail: configBackupTargetStatusDetail(
            target: target,
            profiles: widget.profiles,
          ),
          trailing: target.profileName.isEmpty
              ? ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _busy ? null : _configureStandalone,
                  child: Text(standaloneConfigured ? '编辑连接' : '配置连接'),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ConfigBackupLabeledField(
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
              child: ConfigBackupLabeledField(
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
        const SizedBox(height: 8),
        Text(
          '保存位置：$pathPreview',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '加密密钥由备份目标连接凭证派生，凭证变更后旧快照需要旧凭证才能解密。',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (_isDirty) ...[
          const SizedBox(height: 8),
          Text(
            '目标尚未保存。保存目标，或直接点“立即备份”一并写入。',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ShadButton(
              onPressed: _canBackup ? _backupNow : null,
              child: Text(_backingUp ? '备份中…' : '立即备份'),
            ),
            if (_isDirty || !_settings.enabled)
              ShadButton.outline(
                onPressed: _busy ? null : () => _save(),
                child: Text(_saving && !_backingUp ? '保存中…' : '保存目标'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '备份历史',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 8),
        ConfigBackupHistorySummaryTile(
          theme: theme,
          title: historyTitle,
          detail: historyDetail,
          enabled: !_busy,
          onTap: _openHistoryDialog,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
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
