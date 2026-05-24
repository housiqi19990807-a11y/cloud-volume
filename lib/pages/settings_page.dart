// 设置页：展示连接信息、主题色选择，并允许配置默认下载目录。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = widget.state.config;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36),
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
              '管理远程存储的连接配置、下载位置和外观。',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            ShadCard(
              padding: const EdgeInsets.all(20),
              title: Text(
                '外观',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: theme.colorScheme.foreground,
                ),
              ),
              child: const _ThemePicker(),
            ),
            const SizedBox(height: 20),
            ShadCard(
              padding: const EdgeInsets.all(20),
              title: Text(
                '下载设置',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: theme.colorScheme.foreground,
                ),
              ),
              child: _DownloadDirectorySection(
                theme: theme,
                configuredPath: config.defaultDownloadDirectory,
                saving: _savingDownloadDirectory,
                errorText: _downloadDirectoryError,
                onPickDirectory: () => _pickDownloadDirectory(config),
                onResetDirectory: () => _resetDownloadDirectory(config),
              ),
            ),
            const SizedBox(height: 20),
            ShadCard(
              padding: const EdgeInsets.all(20),
              title: Text(
                '显示设置',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: theme.colorScheme.foreground,
                ),
              ),
              child: _VisibilitySection(
                theme: theme,
                hideDotFiles: config.hideDotFiles,
                saving: _savingVisibility,
                errorText: _visibilityError,
                onChanged: (value) => _saveHideDotFiles(config, value),
              ),
            ),
            const SizedBox(height: 20),
            ShadCard(
              padding: const EdgeInsets.all(20),
              title: Text(
                '连接信息',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: theme.colorScheme.foreground,
                ),
              ),
              child: Column(
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
          ],
        ),
      ),
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
      if (!mounted) {
        return;
      }
      widget.onRefresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadDirectoryError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingDownloadDirectory = false;
        });
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
      if (!mounted) {
        return;
      }
      widget.onRefresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visibilityError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingVisibility = false;
        });
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

class _DownloadDirectorySection extends StatelessWidget {
  const _DownloadDirectorySection({
    required this.theme,
    required this.configuredPath,
    required this.saving,
    required this.errorText,
    required this.onPickDirectory,
    required this.onResetDirectory,
  });

  final ShadThemeData theme;
  final String configuredPath;
  final bool saving;
  final String? errorText;
  final VoidCallback onPickDirectory;
  final VoidCallback onResetDirectory;

  @override
  Widget build(BuildContext context) {
    final hasConfiguredPath = configuredPath.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '下载文件时，保存对话框会优先打开到这个目录；未配置时自动退回系统下载目录。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            hasConfiguredPath ? configuredPath : '系统默认下载目录',
            style: TextStyle(
              fontSize: 12,
              color: hasConfiguredPath
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            ShadButton(
              onPressed: saving ? null : onPickDirectory,
              child: Text(saving ? '保存中...' : '选择目录'),
            ),
            const SizedBox(width: 10),
            ShadButton.outline(
              onPressed: saving || !hasConfiguredPath ? null : onResetDirectory,
              child: const Text('恢复默认'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VisibilitySection extends StatelessWidget {
  const _VisibilitySection({
    required this.theme,
    required this.hideDotFiles,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final bool hideDotFiles;
  final bool saving;
  final String? errorText;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '默认隐藏以 . 开头的目录和文件，便于像 macOS Finder 一样保持文件视图整洁。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '隐藏点文件与点目录',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hideDotFiles ? '当前为默认隐藏' : '当前显示全部文件',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadSwitch(
                value: hideDotFiles,
                onChanged: saving ? null : onChanged,
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
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

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final controller = ThemeController.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主题色',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            for (final preset in AccentPreset.values)
              _ThemeOption(
                preset: preset,
                isSelected: controller.accent == preset,
                onTap: () => controller.onAccentChanged(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final AccentPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? preset.color.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: preset.color.withValues(alpha: 0.3))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: preset.color.withValues(alpha: 0.25),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              preset.label,
              style: TextStyle(fontSize: 12, color: preset.color),
            ),
          ],
        ),
      ),
    );
  }
}
