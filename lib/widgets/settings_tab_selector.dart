// Settings tab selector keeps the desktop settings page grouped by platform
// concerns without introducing separate routes for each subpage.
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsTabItem<T> {
  const SettingsTabItem({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class SettingsTabSelector<T> extends StatelessWidget {
  const SettingsTabSelector({
    super.key,
    required this.theme,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final T value;
  final List<SettingsTabItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.7),
          width: 0.6,
        ),
      ),
      child: Row(
        children: items
            .map(
              (item) => Expanded(
                child: _SettingsTabButton<T>(
                  theme: theme,
                  selected: item.value == value,
                  label: item.label,
                  onTap: () => onChanged(item.value),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SettingsTabButton<T> extends StatelessWidget {
  const _SettingsTabButton({
    required this.theme,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final ShadThemeData theme;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.background
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.foreground.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}
