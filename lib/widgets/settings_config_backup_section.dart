// Settings card for encrypted remote configuration backups.
// Keeps the page compact: backup target setup appears only when the feature
// is enabled, the save location is chosen through a single remote directory
// picker, and the long snapshot history opens through a clickable summary
// into a modal list.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/settings_config_backup_cards.dart';
import 'package:remote_storage/widgets/settings_config_backup_history_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:remote_storage/widgets/settings_config_backup_target.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Sentinel value used by the backup-target selector for the standalone
/// (non-account) storage connection.
const String kStandaloneTargetValue = '__standalone__';

/// Sentinel value used when no backup target has been configured yet.
const String kUnsetTargetValue = '__unset__';

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
    _load();
  }

  bool get _busy => _saving || _backingUp || _listing;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.loadConfigBackupSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
      await _refreshSnapshots(quiet: true);
    } catch (error) {
      if (mounted) setState(() => _error = configBackupFriendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -- Persistence helpers ---------------------------------------------------

  Future<void> _toggleEnabled(bool enabled) async {
    // The whole feature turns on/off here. When enabled, configuration
    // changes always trigger an automatic remote backup — that behavior
    // is baked in and not separately configurable.
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveConfigBackupSettings(
        _settings.copyWith(enabled: enabled),
      );
      if (!mounted) return;
      setState(() => _settings = saved);
      showAppToast(
        context,
        message: enabled ? '已开启配置备份' : '已关闭配置备份',
      );
      if (enabled) {
        await _refreshSnapshots(quiet: true);
      }
    } catch (error) {
      if (mounted) {
        final message = configBackupFriendlyError(error);
        setState(() => _error = message);
        showAppErrorToast(context, title: '保存失败', message: message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _saveTarget(ConfigBackupTarget target) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveConfigBackupSettings(
        _settings.copyWith(target: target),
      );
      if (!mounted) return false;
      setState(() => _settings = saved);
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
    if (!_settings.target.isReady) {
      setState(() => _error = '请先选择可用的备份存储和保存位置。');
      return;
    }
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
    var password = _settings.target.backupPassword;

    // For encrypted snapshots, try the locally-stored password first. Only
    // when that fails (wrong/empty password) do we prompt the user to enter
    // the correct one. This avoids an unnecessary prompt on the normal path
    // where local and remote passwords match.
    if (snapshot.encrypted) {
      // Attempt 1: the password we already have (may be empty on a fresh
      // machine — that will fail fast and fall through to the prompt).
      var decryptOk = password.trim().isNotEmpty;
      if (decryptOk) {
        try {
          await widget.api.verifyBackupPassword(
            _settings.target.copyWith(backupPassword: password),
            snapshot.key,
          );
        } catch (_) {
          decryptOk = false;
        }
      }
      if (!decryptOk) {
        // Attempt 2: prompt for the correct password.
        if (!mounted) return;
        final entered = await _promptForRestorePassword(label);
        if (entered == null) return; // cancelled
        password = entered;
        // Persist so future restores and automatic backups use it.
        await _saveTarget(
          _settings.target.copyWith(backupPassword: entered),
        );
      }
    }
    if (!mounted) return;
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
      final state = password != _settings.target.backupPassword
          ? await widget.api.restoreConfigBackupWithTarget(
              _settings.target.copyWith(backupPassword: password),
              snapshot.key,
              password: password,
            )
          : await widget.api.restoreConfigBackup(snapshot.key);
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

  /// Prompts for the backup password when the locally-stored one does not
  /// decrypt the snapshot. Loops until the entered password verifies or the
  /// user cancels.
  Future<String?> _promptForRestorePassword(String label) async {
    while (true) {
      final controller = TextEditingController();
      var obscure = true;
      String? entered;
      if (!mounted) return null;
      await showAppModalDialog<void>(
        context: context,
        title: const Text('输入备份密码'),
        description: Text('本地备份密码无法解密 $label，请输入正确的备份密码。'),
        maxWidth: 420,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShadInput(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  placeholder: const Text('输入备份密码'),
                  onSubmitted: (value) {
                    entered = value.trim();
                    Navigator.of(dialogContext).pop();
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ShadSwitch(
                      value: !obscure,
                      onChanged: (v) => setDialogState(() => obscure = !v),
                    ),
                    const SizedBox(width: 8),
                    Text('显示密码',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(dialogContext)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6))),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          Builder(
            builder: (dialogContext) => ShadButton.outline(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ),
          Builder(
            builder: (dialogContext) => ShadButton(
              onPressed: () {
                entered = controller.text.trim();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('确定'),
            ),
          ),
        ],
      );
      final value = entered;
      controller.dispose();
      if (value == null || value.isEmpty) return null; // cancelled
      // Verify the entered password against the newest snapshot.
      try {
        await widget.api.verifyBackupPassword(
          _settings.target.copyWith(backupPassword: value),
          '',
        );
        return value;
      } catch (_) {
        if (!mounted) return null;
        showAppErrorToast(context,
            title: '密码错误', message: '输入的密码无法解密备份，请重试。');
        // Loop to prompt again.
      }
    }
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
        onDelete: (snapshot) async {
          await widget.api.deleteConfigBackup(snapshot.key);
        },
        onSnapshotsChanged: (items) {
          if (!mounted) return;
          setState(() => _snapshots = items);
        },
      ),
    );
  }

  // -- Target mutation handlers ---------------------------------------------

  Future<void> _onSelectTarget(String value) async {
    final target = _settings.target;
    if (value == kUnsetTargetValue) {
      // Reset to fully unconfigured.
      await _saveTarget(const ConfigBackupTarget());
      return;
    }
    final newTarget = target.copyWith(
      profileName: value == kStandaloneTargetValue ? '' : value,
    );
    await _saveTarget(newTarget);
  }

  Future<void> _onConfigureStandalone(RemoteStorageConfig config) async {
    // CloudStorageAccountDialog already validates completeness; we just
    // commit the returned config as the standalone target.
    if (!config.isConfigured) return;
    await _saveTarget(
      _settings.target.copyWith(profileName: '', standalone: config),
    );
  }

  Future<void> _onPickSaveLocation(String bucket, String prefix) async {
    await _saveTarget(
      _settings.target.copyWith(bucket: bucket, prefix: prefix),
    );
  }

  Future<void> _onPasswordSaved(String password) async {
    await _saveTarget(
      _settings.target.copyWith(backupPassword: password),
    );
  }

  Future<void> _toggleEncryption(bool enabled) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveConfigBackupSettings(
        _settings.copyWith(encryptionEnabled: enabled),
      );
      if (!mounted) return;
      setState(() => _settings = saved);
    } catch (error) {
      if (mounted) {
        final message = configBackupFriendlyError(error);
        setState(() => _error = message);
        showAppErrorToast(context, title: '保存失败', message: message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

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
          '把账号、代理和显示排序加密备份到远端。开启后会自动在配置变更时备份，也可随时手动备份。可复用已有账号，或单独配置一个不显示在账号列表中的备份连接。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        ConfigBackupSwitchCard(
          theme: theme,
          title: '开启备份',
          description: _settings.enabled
              ? '已开启。账号、代理或排序变更后会在短延迟后自动写入远端，也可手动立即备份。'
              : '关闭后将不会备份配置。开启后可选择备份目标并设置保存位置。',
          value: _settings.enabled,
          enabled: !_busy,
          onChanged: _toggleEnabled,
        ),
        if (_settings.enabled) ...[
          const SizedBox(height: 16),
          ConfigBackupTargetSection(
            theme: theme,
            api: widget.api,
            profiles: widget.profiles,
            target: _settings.target,
            busy: _busy,
            backingUp: _backingUp,
            encryptionEnabled: _settings.encryptionEnabled,
            onSelectTarget: _onSelectTarget,
            onConfigureStandalone: _onConfigureStandalone,
            onPickSaveLocation: _onPickSaveLocation,
            onToggleEncryption: _toggleEncryption,
            onPasswordSaved: _onPasswordSaved,
            onBackupNow: _backupNow,
          ),
          // Only show history once the storage connection is usable.
          if (_settings.target.profileName.isNotEmpty ||
              (_settings.target.standalone != null &&
                  _settings.target.standalone!.isConfigured)) ...[
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
              title: configBackupHistoryTitle(
                loading: _loading || _listing,
                snapshots: _snapshots,
              ),
              detail: configBackupHistoryDetail(
                loading: _loading || _listing,
                snapshots: _snapshots,
              ),
              enabled: !_busy,
              onTap: _openHistoryDialog,
            ),
          ],
        ],
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
