// 设置页分区组件：下载目录、显示选项、文件打开方式与主题色选项。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DownloadDirectorySection extends StatelessWidget {
  const DownloadDirectorySection({
    super.key,
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

class VisibilitySection extends StatelessWidget {
  const VisibilitySection({
    super.key,
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

class FileOpenModeSection extends StatelessWidget {
  const FileOpenModeSection({
    super.key,
    required this.theme,
    required this.fileOpenMode,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final FileOpenMode fileOpenMode;
  final bool saving;
  final String? errorText;
  final ValueChanged<FileOpenMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '默认使用双击打开。双击模式下，单击项目会先进入选中状态，而单击名称仍可直接打开。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        for (final mode in FileOpenMode.values) ...[
          _OpenModeOption(
            theme: theme,
            mode: mode,
            selected: fileOpenMode == mode,
            enabled: !saving,
            onTap: () => onChanged(mode),
          ),
          if (mode != FileOpenMode.values.last) const SizedBox(height: 10),
        ],
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

class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

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
          runSpacing: 10,
          children: [
            for (final preset in AccentPreset.values)
              ThemeOption(
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

class ThemeOption extends StatelessWidget {
  const ThemeOption({
    super.key,
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

class _OpenModeOption extends StatelessWidget {
  const _OpenModeOption({
    required this.theme,
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ShadThemeData theme;
  final FileOpenMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = theme.colorScheme.primary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.28)
                : theme.colorScheme.border.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: selected ? accent : theme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode == FileOpenMode.doubleClick ? '双击打开' : '单击打开',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mode == FileOpenMode.doubleClick
                        ? '单击项目用于选中，名称可直接打开，适合多选操作。'
                        : '单击整个项目立即打开，更接近传统文件浏览器。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
