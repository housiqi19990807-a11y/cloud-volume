part of 'settings_page.dart';

// Layout helpers for the settings page's left-side group rail and right-side
// content area. Extracted from settings_page.dart to keep the main file under
// the 500-line limit.

/// Vertical navigation rail mirroring the former top ShadTabs entries.
extension _SettingsLayout on _SettingsPageState {
  Widget _buildGroupRail(ShadThemeData theme, List<_SettingsTab> tabs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tab in tabs) ...[
          _buildGroupTile(theme, tab),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  /// A single clickable group entry in the left rail.
  ///
  /// Delegates to [_SettingsGroupTile], a StatefulWidget, so hover state is
  /// tracked and rebuilt correctly (see the class doc for why an extension
  /// cannot own hover state).
  Widget _buildGroupTile(ShadThemeData theme, _SettingsTab tab) {
    final active = tab == _activeTab;
    final label = switch (tab) {
      _SettingsTab.general => '通用设置',
      _SettingsTab.windows => 'Windows 设置',
      _SettingsTab.about => '关于',
    };
    return _SettingsGroupTile(
      accent: theme.colorScheme.accent,
      foreground: theme.colorScheme.foreground,
      mutedForeground: theme.colorScheme.mutedForeground,
      label: label,
      active: active,
      // _updateState routes through the State subclass so this extension
      // does not touch the protected setState directly.
      onTap: () => _updateState(() => _activeTab = tab),
    );
  }

  /// Returns the section list for whichever tab is currently active.
  List<Widget> _buildActiveContent(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    switch (_activeTab) {
      case _SettingsTab.general:
        return _buildGeneralSections(theme, config);
      case _SettingsTab.windows:
        return _buildWindowsSections(theme, config);
      case _SettingsTab.about:
        return _buildAboutSections(theme);
    }
  }
}

/// Self-contained hover-aware navigation tile for the settings group rail.
///
/// Hover handling follows the project-wide pattern (see `_SidebarNavItem` in
/// main_layout_page.dart): a StatefulWidget holds a `_hovered` flag that is
/// toggled by [MouseRegion.onEnter] / [MouseRegion.onExit] and drives
/// background color, text color, and cursor via an [AnimatedContainer].
///
/// **Why this must be a StatefulWidget, not inline in an extension:**
/// an `extension on _SettingsPageState` can read and call methods on the
/// State, but it has *no place to store mutable fields*. Wrapping a
/// `MouseRegion(onEnter/onExit: ...)` whose callback needs to toggle a flag
/// and rebuild has nowhere to put that flag — the callbacks would either be
/// no-ops or require reaching back into the host State's private fields,
/// which is fragile. Every hover-aware clickable row in this codebase
/// (`_SidebarNavItem`, `FileListTile`, `TransferTaskRow`, …) is a dedicated
/// StatefulWidget for exactly this reason.
class _SettingsGroupTile extends StatefulWidget {
  const _SettingsGroupTile({
    required this.accent,
    required this.foreground,
    required this.mutedForeground,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final Color accent;
  final Color foreground;
  final Color mutedForeground;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SettingsGroupTile> createState() => _SettingsGroupTileState();
}

class _SettingsGroupTileState extends State<_SettingsGroupTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final ac = widget.accent;

    final fg = active
        ? widget.foreground
        : _hovered
            ? ac.withValues(alpha: 0.9)
            : widget.mutedForeground;
    final baseBg = active ? ac.withValues(alpha: 0.12) : Colors.transparent;
    final hoverOverlay = active
        ? Colors.transparent
        : ac.withValues(alpha: _hovered ? 0.1 : 0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Idle cursor stays as the basic arrow so it does not get stuck on a
      // pointing hand inherited from an ancestor (project convention).
      cursor: _hovered ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Color.alphaBlend(hoverOverlay, baseBg),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
