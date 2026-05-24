// Finder 风格的文件网格单元：无边框、图标居中、名称压在图标下方。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 文件管理页的 Finder 风格网格项。
class FileGridItem extends StatelessWidget {
  const FileGridItem({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onDoubleTap,
    this.onTitleTap,
    this.onSelectionTap,
    this.isSelected = false,
    this.showSelectionControl = false,
    this.onSecondaryTapDown,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTitleTap;
  final VoidCallback? onSelectionTap;
  final bool isSelected;
  final bool showSelectionControl;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return _HoverBuilder(
      builder: (hovered) {
        return GestureDetector(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onSecondaryTapDown: onSecondaryTapDown,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : hovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    leading,
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTitleTap,
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.foreground,
                            height: 1.25,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (showSelectionControl)
                Positioned(
                  top: 2,
                  right: 2,
                  child: _SelectionIndicator(
                    isSelected: isSelected,
                    onTap: onSelectionTap,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: isSelected ? accent : theme.colorScheme.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? accent
                : theme.colorScheme.border.withValues(alpha: 0.9),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 追踪鼠标 hover，用于 Finder 风格轻量反馈。
class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}
