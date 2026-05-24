// Left brand panel for the config setup page.
// Deep dark panel with hero text, accent color picker, and config path display.
// All decorative colors derive from the current accent preset.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';

class ConfigLeftPanel extends StatelessWidget {
  const ConfigLeftPanel({super.key, required this.configPath});

  final String configPath;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = ThemeController.of(context).accent;
    final ac = accent.color;

    // Base dark background, tinted slightly by the accent.
    final bg = Color.lerp(const Color(0xff0a0f1e), ac, 0.08)!;
    final bgTop = Color.lerp(const Color(0xff060a16), ac, 0.06)!;

    // Foreground colors stay bright for readability.
    const fg = Color(0xfff0f4ff);
    final muted = Color.lerp(const Color(0xff8b9dc3), ac, 0.15)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bg],
          stops: const [0.0, 0.15],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 32,
          right: 32,
          top: 40,
          bottom: 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand mark with accent-tinted container.
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ac.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ac.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.cloud_outlined, size: 20, color: ac),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Remote Storage',
                    style: theme.textTheme.large.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(flex: 2),
            // Hero text
            Text(
              '连接你的\nS3 兼容\n对象存储',
              style: theme.textTheme.h3.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                height: 1.2,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: Text(
                '输入对象存储凭证以开始使用。\n配置将保存至：',
                style: theme.textTheme.muted.copyWith(
                  color: muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Config path box with accent-tinted border.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Color.lerp(const Color(0xff111827), ac, 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ac.withValues(alpha: 0.15)),
              ),
              child: SelectableText(
                configPath,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Spacer(flex: 3),
            // Accent color picker
            _AccentPicker(),
            const SizedBox(height: 16),
            // Security note
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 13,
                  color: muted.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '凭证仅保存在本地',
                    style: TextStyle(
                      color: muted.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact accent-color selector shown in the left panel.
class _AccentPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.of(context);
    final accent = controller.accent.color;
    final muted = Color.lerp(const Color(0xff8b9dc3), accent, 0.15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主题色',
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in AccentPreset.values)
              _AccentDot(
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

class _AccentDot extends StatelessWidget {
  const _AccentDot({
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
      child: Tooltip(
        message: preset.label,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: preset.color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: Colors.white, width: 2.5)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: preset.color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}
