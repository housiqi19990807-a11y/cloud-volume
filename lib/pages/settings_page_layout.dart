part of 'settings_page.dart';

// Layout helpers for the settings page's left-side group rail and right-side
// content area. Extracted from settings_page.dart to keep the main file under
// the 500-line limit.

/// A labelled group of tabs shown as a section header + tile list in the rail.
class _SettingsRailGroup {
  const _SettingsRailGroup({required this.header, required this.tabs});

  final String header;
  final List<_SettingsTab> tabs;
}

/// Vertical navigation rail with section headers. Each group (通用 / Windows /
/// 关于) gets a muted header label followed by its tab tiles.
extension _SettingsLayout on _SettingsPageState {
  /// Builds the ordered group list, conditionally including the Windows group.
  List<_SettingsRailGroup> _railGroups() {
    return [
      _SettingsRailGroup(
        header: '通用',
        tabs: [
          _SettingsTab.update,
          _SettingsTab.proxy,
          _SettingsTab.appearance,
          if (widget.api.capabilities.supportsDownloadDirectory)
            _SettingsTab.download,
          _SettingsTab.cache,
          _SettingsTab.visibility,
          _SettingsTab.sync,
          _SettingsTab.trash,
          if (!isWebPlatform) _SettingsTab.webdav,
          _SettingsTab.resetAccount,
          _SettingsTab.configManage,
        ],
      ),
      if (_showsWindowsTab)
        _SettingsRailGroup(
          header: 'Windows',
          tabs: [
            _SettingsTab.windowsEntry,
            _SettingsTab.windowsWriteback,
            _SettingsTab.windowsMount,
          ],
        ),
      _SettingsRailGroup(
        header: '关于',
        tabs: [_SettingsTab.about],
      ),
    ];
  }

  Widget _buildGroupRail(ShadThemeData theme) {
    final groups = _railGroups();
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_railHeader(theme, group.header));
      for (final tab in group.tabs) {
        children.add(_buildGroupTile(theme, tab));
        children.add(const SizedBox(height: 2));
      }
      children.add(const SizedBox(height: 16));
    }
    // Remove trailing spacer
    if (children.isNotEmpty) children.removeLast();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _railHeader(ShadThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6, left: 14),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }

  /// A single clickable group entry in the left rail.
  ///
  /// Delegates to [_SettingsGroupTile], a StatefulWidget, so hover state is
  /// tracked and rebuilt correctly (see the class doc for why an extension
  /// cannot own hover state).
  Widget _buildGroupTile(ShadThemeData theme, _SettingsTab tab) {
    final active = tab == _activeTab;
    return _SettingsGroupTile(
      accent: theme.colorScheme.accent,
      foreground: theme.colorScheme.foreground,
      mutedForeground: theme.colorScheme.mutedForeground,
      label: _tabLabel(tab),
      active: active,
      // _updateState routes through the State subclass so this extension
      // does not touch the protected setState directly.
      onTap: () => _updateState(() => _activeTab = tab),
    );
  }

  /// Human-readable label for each tab.
  String _tabLabel(_SettingsTab tab) {
    return switch (tab) {
      _SettingsTab.update => '应用更新',
      _SettingsTab.proxy => '网络代理',
      _SettingsTab.appearance => '外观',
      _SettingsTab.download => '下载设置',
      _SettingsTab.cache => '缓存设置',
      _SettingsTab.visibility => '显示设置',
      _SettingsTab.sync => '同步设置',
      _SettingsTab.trash => '回收站',
      _SettingsTab.webdav => 'WebDAV 凭据',
      _SettingsTab.resetAccount => '账号重置',
      _SettingsTab.configManage => '配置管理',
      _SettingsTab.windowsEntry => 'Windows 入口',
      _SettingsTab.windowsWriteback => '写回并发',
      _SettingsTab.windowsMount => '挂载恢复',
      _SettingsTab.about => '关于云卷',
    };
  }

  /// Returns the section list for whichever tab is currently active.
  List<Widget> _buildActiveContent(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    switch (_activeTab) {
      case _SettingsTab.update:
        return _buildUpdateSection(theme, config);
      case _SettingsTab.proxy:
        return _buildProxySection(theme, config);
      case _SettingsTab.appearance:
        return _buildAppearanceSection(theme);
      case _SettingsTab.download:
        return _buildDownloadSection(theme, config);
      case _SettingsTab.cache:
        return _buildCacheSection(theme, config);
      case _SettingsTab.visibility:
        return _buildVisibilitySection(theme, config);
      case _SettingsTab.sync:
        return _buildSyncSection(theme, config);
      case _SettingsTab.trash:
        return _buildTrashSection(theme, config);
      case _SettingsTab.webdav:
        return _buildWebdavSection(theme, config);
      case _SettingsTab.resetAccount:
        return _buildResetAccountSection(theme);
      case _SettingsTab.configManage:
        return _buildConfigManageSection(theme);
      case _SettingsTab.windowsEntry:
        return _buildWindowsEntrySection(theme, config);
      case _SettingsTab.windowsWriteback:
        return _buildWindowsWritebackSection(theme, config);
      case _SettingsTab.windowsMount:
        return _buildWindowsMountSection(theme);
      case _SettingsTab.about:
        return _buildAboutSection(theme);
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
