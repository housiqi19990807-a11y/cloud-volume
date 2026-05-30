// 设置页集中管理主题、下载目录、可见性和 Windows 挂载模式等偏好。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/settings_sections.dart';
import 'package:remote_storage/widgets/settings_trash_section.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.api,
    required this.onEditConfig,
    required this.onRefresh,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _savingDownloadDirectory = false;
  String? _downloadDirectoryError;
  bool _savingVisibility = false;
  String? _visibilityError;
  bool _savingTrashSettings = false;
  String? _trashSettingsError;
  bool _savingWindowsMountMode = false;
  String? _windowsMountModeError;
  bool _savingWindowsThisPcEntry = false;
  String? _windowsThisPcEntryError;
  bool _resettingWindowsMounts = false;
  String? _windowsMountResetError;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = widget.state.config;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设置',
              style: theme.textTheme.h3.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '管理远程存储的连接配置、下载目录、界面偏好和挂载行为。',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            _buildCard(theme, '外观', const ThemePicker()),
            const SizedBox(height: 20),
            _buildCard(
              theme,
              '下载设置',
              DownloadDirectorySection(
                theme: theme,
                configuredPath: config.defaultDownloadDirectory,
                saving: _savingDownloadDirectory,
                errorText: _downloadDirectoryError,
                onPickDirectory: () => _pickDownloadDirectory(config),
                onResetDirectory: () => _resetDownloadDirectory(config),
              ),
            ),
            const SizedBox(height: 20),
            _buildCard(
              theme,
              '显示设置',
              VisibilitySection(
                theme: theme,
                hideDotFiles: config.hideDotFiles,
                saving: _savingVisibility,
                errorText: _visibilityError,
                onChanged: (value) => _saveHideDotFiles(config, value),
              ),
            ),
            if (Platform.isWindows) ...[
              const SizedBox(height: 20),
              _buildCard(
                theme,
                'Windows 挂载模式',
                WindowsMountModeSection(
                  theme: theme,
                  mode: config.windowsMountMode,
                  saving: _savingWindowsMountMode,
                  errorText: _windowsMountModeError,
                  onChanged: (value) => _saveWindowsMountMode(config, value),
                ),
              ),
              const SizedBox(height: 20),
              _buildCard(
                theme,
                'Windows 入口',
                WindowsThisPcEntrySection(
                  theme: theme,
                  enabled: config.windowsThisPcEntryEnabled,
                  saving: _savingWindowsThisPcEntry,
                  errorText: _windowsThisPcEntryError,
                  onChanged: (value) =>
                      _saveWindowsThisPcEntry(config, value),
                ),
              ),
              const SizedBox(height: 20),
              _buildCard(
                theme,
                'Windows 挂载恢复',
                WindowsMountRecoverySection(
                  theme: theme,
                  busy: _resettingWindowsMounts,
                  errorText: _windowsMountResetError,
                  onReset: _forceResetWindowsMounts,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildCard(
              theme,
              '回收站',
              TrashSettingsSection(
                theme: theme,
                directoryName: config.trashDirectoryName,
                retentionDays: config.trashRetentionDays,
                saving: _savingTrashSettings,
                errorText: _trashSettingsError,
                onSave: (directoryName, retentionDays) =>
                    _saveTrashSettings(config, directoryName, retentionDays),
              ),
            ),
            const SizedBox(height: 20),
            _buildCard(
              theme,
              '连接信息',
              Column(
                children: [
                  _infoRow(theme, '端点地址', config.endpoint),
                  const SizedBox(height: 8),
                  _infoRow(
                    theme,
                    '区域',
                    config.region.isEmpty ? 'auto' : config.region,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(theme, '路径风格', config.usePathStyle ? '启用' : '禁用'),
                  const SizedBox(height: 8),
                  _infoRow(theme, '配置路径', widget.state.configPath),
                  const SizedBox(height: 8),
                  _infoRow(theme, '访问密钥 ID', _maskedKey(config.accessKeyId)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ShadButton(
                  onPressed: widget.onEditConfig,
                  child: const Text('重新配置'),
                ),
                const SizedBox(width: 10),
                ShadButton.outline(
                  onPressed: widget.onRefresh,
                  child: const Text('刷新状态'),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(ShadThemeData theme, String title, Widget child) {
    return ShadCard(
      padding: const EdgeInsets.all(20),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: theme.colorScheme.foreground,
        ),
      ),
      child: child,
    );
  }

  Future<void> _pickDownloadDirectory(RemoteStorageConfig config) async {
    final initialDirectory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择默认下载目录',
      initialDirectory: initialDirectory,
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    await _saveDownloadDirectory(config, path.trim());
  }

  Future<void> _resetDownloadDirectory(RemoteStorageConfig config) async {
    await _saveDownloadDirectory(config, '');
  }

  Future<void> _saveDownloadDirectory(
    RemoteStorageConfig config,
    String path,
  ) async {
    setState(() {
      _savingDownloadDirectory = true;
      _downloadDirectoryError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(defaultDownloadDirectory: path),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloadDirectoryError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingDownloadDirectory = false);
      }
    }
  }

  Future<void> _saveHideDotFiles(
    RemoteStorageConfig config,
    bool hideDotFiles,
  ) async {
    setState(() {
      _savingVisibility = true;
      _visibilityError = null;
    });
    try {
      await widget.api.saveConfig(config.copyWith(hideDotFiles: hideDotFiles));
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _visibilityError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingVisibility = false);
      }
    }
  }

  Future<void> _saveTrashSettings(
    RemoteStorageConfig config,
    String directoryName,
    int retentionDays,
  ) async {
    setState(() {
      _savingTrashSettings = true;
      _trashSettingsError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(
          trashDirectoryName: directoryName,
          trashRetentionDays: retentionDays,
        ),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _trashSettingsError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingTrashSettings = false);
      }
    }
  }

  Future<void> _saveWindowsMountMode(
    RemoteStorageConfig config,
    WindowsMountMode? mode,
  ) async {
    if (mode == null || mode == config.windowsMountMode) {
      return;
    }
    setState(() {
      _savingWindowsMountMode = true;
      _windowsMountModeError = null;
    });
    try {
      await widget.api.saveConfig(config.copyWith(windowsMountMode: mode));
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _windowsMountModeError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingWindowsMountMode = false);
      }
    }
  }

  Future<void> _saveWindowsThisPcEntry(
    RemoteStorageConfig config,
    bool enabled,
  ) async {
    if (enabled == config.windowsThisPcEntryEnabled) {
      return;
    }
    setState(() {
      _savingWindowsThisPcEntry = true;
      _windowsThisPcEntryError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(windowsThisPcEntryEnabled: enabled),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _windowsThisPcEntryError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingWindowsThisPcEntry = false);
      }
    }
  }

  Future<void> _forceResetWindowsMounts() async {
    setState(() {
      _resettingWindowsMounts = true;
      _windowsMountResetError = null;
    });
    try {
      await widget.api.cleanupMounts();
      if (!mounted) return;
      showAppToast(
        context,
        title: '挂载状态已重置',
        message: '已强制清理 Windows 挂载与残留 sync root。',
      );
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _windowsMountResetError = error.toString());
      showAppErrorToast(context, title: '挂载重置失败', message: error.toString());
    } finally {
      if (mounted) {
        setState(() => _resettingWindowsMounts = false);
      }
    }
  }

  Widget _infoRow(ShadThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _maskedKey(String key) {
    if (key.length <= 6) {
      return key;
    }
    return '${key.substring(0, 4)}${'•' * (key.length - 6)}${key.substring(key.length - 2)}';
  }
}
