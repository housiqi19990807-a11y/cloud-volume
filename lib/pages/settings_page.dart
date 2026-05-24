// 设置页：展示连接信息、主题色选择，支持重新配置和刷新状态。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.onEditConfig,
    required this.onRefresh,
  });

  final BootstrapState state;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = state.config;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 页面标题。
            Text(
              '设置',
              style: theme.textTheme.h3.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '管理远程存储的连接配置和外观。',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),

            // 外观设置卡片。
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

            // 连接信息卡片。
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
                  _infoRow(theme, '配置路径', state.configPath),
                  const SizedBox(height: 8),
                  _infoRow(theme, '访问密钥 ID', _maskedKey(config.accessKeyId)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 操作按钮。
            Row(
              children: [
                ShadButton(onPressed: onEditConfig, child: const Text('重新配置')),
                const SizedBox(width: 10),
                ShadButton.outline(
                  onPressed: onRefresh,
                  child: const Text('刷新状态'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    if (key.length <= 6) return key;
    return '${key.substring(0, 4)}${'•' * (key.length - 6)}${key.substring(key.length - 2)}';
  }
}

/// 主题色选择器。
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
                          color: preset.color.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              preset.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? preset.color
                    : Theme.of(context).brightness == Brightness.light
                    ? const Color(0xff64748b)
                    : const Color(0xff94a3b8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
