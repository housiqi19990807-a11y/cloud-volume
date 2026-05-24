// Left brand panel for the config setup page.
// Bright accent-tinted panel with slogan and theme color picker.
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

    // Bright background: white base tinted with accent.
    final bg = Color.lerp(const Color(0xfff8faff), ac, 0.04)!;
    final bgTop = Color.lerp(const Color(0xffeef2ff), ac, 0.08)!;

    // Text colors.
    final heading = Color.lerp(const Color(0xff1e293b), ac, 0.25)!;
    final muted = Color.lerp(const Color(0xff64748b), ac, 0.12)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bg],
          stops: const [0.0, 0.4],
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
            // Brand mark.
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ac.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ac.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.cloud_outlined, size: 22, color: ac),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Remote Storage',
                    style: theme.textTheme.large.copyWith(
                      color: heading,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(flex: 2),
            // Slogan.
            Text(
              '你的云端\n存储管理器',
              style: theme.textTheme.h3.copyWith(
                color: heading,
                fontWeight: FontWeight.w700,
                height: 1.25,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '安全、高效地管理你的远程存储。',
              style: theme.textTheme.muted.copyWith(
                color: muted,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const Spacer(flex: 3),
            // Accent color picker.
            _AccentPicker(muted: muted),
            const SizedBox(height: 16),
            // Security note.
            Row(
              children: [
                Icon(Icons.lock_outline, size: 13, color: muted),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '凭证仅保存在本地',
                    style: TextStyle(color: muted, fontSize: 11),
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
  const _AccentPicker({required this.muted});

  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.of(context);

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
                ? Border.all(
                    color: Color.lerp(preset.color, Colors.black, 0.3)!,
                    width: 2.5,
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: preset.color.withValues(alpha: 0.4),
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
