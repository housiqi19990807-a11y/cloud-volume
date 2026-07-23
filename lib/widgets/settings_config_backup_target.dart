// Backup target configuration: account selector, standalone storage dialog,
// single save-location picker, and encryption-key info modal.
// Extracted from settings_config_backup_section.dart to stay under 500 lines.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_cards.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:remote_storage/widgets/settings_config_backup_section.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Renders the backup-target sub-card shown only when backup is enabled.
/// The selector offers existing accounts plus a "独立备份存储" option whose
/// connection form opens lazily on click. Save location is a single remote
/// directory picker (bucket + prefix in one action).
class ConfigBackupTargetSection extends StatelessWidget {
  const ConfigBackupTargetSection({
    super.key,
    required this.theme,
    required this.api,
    required this.profiles,
    required this.target,
    required this.busy,
    required this.backingUp,
    required this.onSelectTarget,
    required this.onConfigureStandalone,
    required this.onPickSaveLocation,
    required this.onBackupNow,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final List<ProfileInfo> profiles;
  final ConfigBackupTarget target;
  final bool busy;
  final bool backingUp;
  final ValueChanged<String> onSelectTarget;
  final ValueChanged<RemoteStorageConfig> onConfigureStandalone;
  final void Function(String bucket, String prefix) onPickSaveLocation;
  final VoidCallback onBackupNow;

  @override
  Widget build(BuildContext context) {
    // Default state: no profile and no standalone configured yet.
    final hasProfile = target.profileName.isNotEmpty;
    final hasStandalone =
        target.standalone != null && target.standalone!.isConfigured;
    final selectorValue = hasProfile
        ? target.profileName
        : (hasStandalone ? kStandaloneTargetValue : kUnsetTargetValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('备份目标',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground)),
        const SizedBox(height: 8),
        _BackupTargetSelector(
          theme: theme,
          profiles: profiles,
          value: selectorValue,
          enabled: !busy,
          onChanged: onSelectTarget,
        ),
        const SizedBox(height: 10),
        _StandaloneTargetCard(
          theme: theme,
          api: api,
          profiles: profiles,
          target: target,
          busy: busy,
          onConfigured: onConfigureStandalone,
        ),
        const SizedBox(height: 12),
        _SaveLocationPicker(
          theme: theme,
          api: api,
          target: target,
          busy: busy,
          onPicked: onPickSaveLocation,
        ),
        const SizedBox(height: 8),
        _EncryptionKeyButton(theme: theme),
        const SizedBox(height: 14),
        ShadButton(
          onPressed: target.isReady && !busy ? onBackupNow : null,
          child: Text(backingUp ? '备份中…' : '立即备份'),
        ),
      ],
    );
  }
}

// Dropdown: existing accounts vs standalone storage (no parenthetical).
class _BackupTargetSelector extends StatelessWidget {
  const _BackupTargetSelector({
    required this.theme,
    required this.profiles,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final List<ProfileInfo> profiles;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  String _label(String v) {
    if (v == kUnsetTargetValue) return '未配置';
    if (v == kStandaloneTargetValue) return '独立备份存储';
    for (final p in profiles) {
      if (p.name == v) return configBackupProfileLabel(p);
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ShadSelect<String>(
        key: ValueKey<String>(value),
        initialValue: value,
        minWidth: 320,
        selectedOptionBuilder: (context, selected) => Text(_label(selected)),
        options: [
          const ShadOption(value: kUnsetTargetValue, child: Text('未配置')),
          ...profiles.map((p) => ShadOption(
              value: p.name, child: Text(configBackupProfileLabel(p)))),
          const ShadOption(value: kStandaloneTargetValue, child: Text('独立备份存储')),
        ],
        onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
      ),
    );
  }
}

// Standalone: status card + lazy configure/edit button.
// Profile selected: read-only summary.
class _StandaloneTargetCard extends StatefulWidget {
  const _StandaloneTargetCard({
    required this.theme,
    required this.api,
    required this.profiles,
    required this.target,
    required this.busy,
    required this.onConfigured,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final List<ProfileInfo> profiles;
  final ConfigBackupTarget target;
  final bool busy;
  final ValueChanged<RemoteStorageConfig> onConfigured;

  @override
  State<_StandaloneTargetCard> createState() => _StandaloneTargetCardState();
}

class _StandaloneTargetCardState extends State<_StandaloneTargetCard> {
  bool get _isStandalone => widget.target.profileName.isEmpty;
  bool get _isConfigured =>
      widget.target.standalone != null && widget.target.standalone!.isConfigured;

  Future<void> _openStandaloneDialog() async {
    final standalone = widget.target.standalone;
    RemoteStorageConfig? result;
    await showAppModal<void>(
      context: context,
      builder: (_) => CloudStorageAccountDialog(
        api: widget.api,
        initialConfig: standalone,
        editing: standalone != null,
        onListBuckets: widget.api.listBuckets,
        onStartBaiduPanAuthorization: widget.api.startBaiduPanAuthorization,
        onAuthorizeBaiduPan: widget.api.authorizeBaiduPan,
        onSave: (config) async {
          if (!config.isConfigured) return false;
          result = config;
          return true;
        },
      ),
    );
    if (result != null && mounted) widget.onConfigured(result!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (!_isStandalone) {
      // A profile is selected — show a read-only summary.
      return ConfigBackupStatusCard(
        theme: theme,
        title: configBackupTargetStatusTitle(
            target: widget.target, profiles: widget.profiles),
        detail: configBackupTargetStatusDetail(
            target: widget.target, profiles: widget.profiles),
      );
    }
    if (!_isConfigured) {
      // Standalone selected but not yet set up (or completely fresh) — show a
      // configure button to open the storage dialog.
      return ConfigBackupStatusCard(
        theme: theme,
        title: '尚未配置备份目标',
        detail: '点击右侧按钮配置一个不显示在账号列表中的备份连接。',
        trailing: ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: widget.busy ? null : _openStandaloneDialog,
          child: const Text('配置连接'),
        ),
      );
    }
    // Standalone fully configured — show summary + edit button.
    return ConfigBackupStatusCard(
      theme: theme,
      title: configBackupTargetStatusTitle(
          target: widget.target, profiles: widget.profiles),
      detail: configBackupTargetStatusDetail(
          target: widget.target, profiles: widget.profiles),
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: widget.busy ? null : _openStandaloneDialog,
        child: const Text('编辑连接'),
      ),
    );
  }
}

// Single "选择保存位置" picker: opens remote directory browser, stores
// bucket + prefix together.
class _SaveLocationPicker extends StatefulWidget {
  const _SaveLocationPicker({
    required this.theme,
    required this.api,
    required this.target,
    required this.busy,
    required this.onPicked,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final ConfigBackupTarget target;
  final bool busy;
  final void Function(String bucket, String prefix) onPicked;

  @override
  State<_SaveLocationPicker> createState() => _SaveLocationPickerState();
}

class _SaveLocationPickerState extends State<_SaveLocationPicker> {
  Future<RemoteStorageConfig?> _resolveConfig() async {
    if (widget.target.profileName.isEmpty) return widget.target.standalone;
    try {
      return await widget.api.loadProfile(widget.target.profileName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openPicker() async {
    final config = await _resolveConfig();
    if (!mounted) return;
    if (config == null || !config.isConfigured) {
      showAppErrorToast(context,
          title: '无法打开目录选择器', message: '请先选择一个已配置的备份存储。');
      return;
    }
    List<FileManagerBucketEntry> entries;
    try {
      final buckets = await widget.api.listBuckets(config);
      entries = buckets
          .map((b) => FileManagerBucketEntry.fromBucketInfo(
                bucket: b,
                profileName: widget.target.profileName.isEmpty
                    ? '__standalone__'
                    : widget.target.profileName,
                sourceLabel: config.displayName.isEmpty
                    ? config.storageType.label
                    : config.displayName,
                config: config,
              ))
          .toList();
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context,
            title: '读取存储桶失败', message: configBackupFriendlyError(error));
      }
      return;
    }
    if (!mounted) return;
    final initialProfile = entries.isEmpty ? '' : entries.first.profileName;
    final result = await showRemoteDirectoryPicker(
      context: context,
      api: widget.api,
      buckets: entries,
      initial: RemoteDirectoryResult(
        bucket: widget.target.bucket,
        prefix: widget.target.prefix,
        profileName: initialProfile,
        config: config,
      ),
    );
    if (result != null) widget.onPicked(result.bucket, result.prefix);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final hasLocation = widget.target.bucket.trim().isNotEmpty;
    final preview = configBackupPathPreview(
        bucket: widget.target.bucket, prefix: widget.target.prefix);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('保存位置',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground)),
        const SizedBox(height: 6),
        _PickerButton(
          theme: theme,
          label: hasLocation ? preview : '选择保存位置',
          hasLocation: hasLocation,
          enabled: !widget.busy,
          onPressed: _openPicker,
        ),
      ],
    );
  }
}

/// Clickable "选择保存位置" button (hover-aware per AGENTS.md rules).
class _PickerButton extends StatefulWidget {
  const _PickerButton({
    required this.theme,
    required this.label,
    required this.hasLocation,
    required this.enabled,
    required this.onPressed,
  });

  final ShadThemeData theme;
  final String label;
  final bool hasLocation;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_PickerButton> createState() => _PickerButtonState();
}

class _PickerButtonState extends State<_PickerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final interaction = ListInteractionColors.fromTheme(theme);
    final bg = interaction.rowBackground(
        selected: false, hovered: _hovered && widget.enabled, pressed: false);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(bg, theme.colorScheme.background),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.border),
          ),
          child: Row(
            children: [
              Icon(
                widget.hasLocation
                    ? Icons.folder_open_rounded
                    : Icons.create_new_folder_outlined,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.hasLocation
                        ? theme.colorScheme.foreground
                        : theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: theme.colorScheme.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

// Encryption-key info button: opens a modal explaining key derivation.
// The key itself is derived server-side from storage credentials.
class _EncryptionKeyButton extends StatelessWidget {
  const _EncryptionKeyButton({required this.theme});
  final ShadThemeData theme;

  Future<void> _openInfo(BuildContext context) async {
    await showAppModalDialog<void>(
      context: context,
      title: const Text('备份密钥'),
      description: const Text('配置备份使用加密密钥保护，密钥由备份存储的连接凭证派生。'),
      maxWidth: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '加密密钥会根据你选择的备份存储（账号或独立存储）的连接凭证自动派生，无需手动输入。',
            style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: theme.colorScheme.mutedForeground),
          ),
          const SizedBox(height: 10),
          Text(
            '如果之后修改了备份存储的连接凭证（如访问密钥、密码等），之前生成的备份仍需使用旧凭证才能解密。建议在变更凭证前先做一次手动备份，并妥善保管旧凭证。',
            style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: theme.colorScheme.mutedForeground),
          ),
        ],
      ),
      actions: [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => _openInfo(context),
        child: const Text('配置备份密钥'),
      ),
    );
  }
}
