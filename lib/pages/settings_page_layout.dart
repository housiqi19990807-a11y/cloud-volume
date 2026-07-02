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
  Widget _buildGroupTile(ShadThemeData theme, _SettingsTab tab) {
    final active = tab == _activeTab;
    final label = switch (tab) {
      _SettingsTab.general => '通用设置',
      _SettingsTab.windows => 'Windows 设置',
      _SettingsTab.about => '关于',
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
     child: GestureDetector(
        // _updateState routes through the State subclass so this extension
        // does not touch the protected setState directly.
        onTap: () => _updateState(() => _activeTab = tab),
       child: Container(
         padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
         decoration: BoxDecoration(
           color: active
                ? theme.colorScheme.accent.withValues(alpha: 0.12)
               : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
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
