// 设置页负责按“通用 / Windows / 关于”分组展示配置，避免平台专属选项把通用设置挤在同一长页里。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/utils/app_runtime_version.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/settings_about_section.dart';
import 'package:remote_storage/widgets/settings_reset_user_config_section.dart';
import 'package:remote_storage/widgets/settings_sections.dart'
    show
        DownloadDirectorySection,
        ThemePicker,
        VisibilitySection,
        WebDavCredentialsSection;
import 'package:remote_storage/widgets/settings_cache_section.dart';
import 'package:remote_storage/widgets/settings_proxy_section.dart';
import 'package:remote_storage/widgets/settings_sync_section.dart';
import 'package:remote_storage/widgets/settings_trash_section.dart';
import 'package:remote_storage/widgets/settings_update_section.dart';
import 'package:remote_storage/widgets/windows_settings_sections.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'settings_page_actions.dart';
part 'settings_page_layout.dart';

enum _SettingsTab { general, windows, about }

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
  _SettingsTab _activeTab = _SettingsTab.general;
  bool _savingDownloadDirectory = false;
  String? _downloadDirectoryError;
  bool _savingCacheDirectory = false;
  String? _cacheDirectoryError;
  CacheStats? _cacheStats;
  bool _loadingCacheStats = false;
  bool _cleaningCache = false;
  bool _openingCache = false;
  bool _savingCacheRules = false;
  String? _cacheRulesError;
  bool _savingVisibility = false;
  String? _visibilityError;
  bool _savingTrashSettings = false;
  String? _trashSettingsError;
  bool _savingWritebackQuietSeconds = false;
  String? _writebackQuietSecondsError;
  bool _savingMountMetadataCache = false;
  String? _mountMetadataCacheError;
  bool _savingWebdavCredentials = false;
  String? _webdavCredentialsError;
  bool _savingWindowsThisPcEntry = false;
  String? _windowsThisPcEntryError;
  bool _savingWindowsWritebackConcurrency = false;
  String? _windowsWritebackConcurrencyError;
  bool _resettingWindowsMounts = false;
  String? _windowsMountResetError;
  bool _cleaningStaleWindowsProcesses = false;
  bool _resettingUserConfig = false;
  String? _resetUserConfigError;

  bool get _showsWindowsTab => isWindowsPlatform;

  void _updateState(VoidCallback action) => setState(action);

 @override
 Widget build(BuildContext context) {
   final theme = ShadTheme.of(context);
   final config = widget.state.config;

    // Build the ordered list of available tabs so the sidebar reflects the
    // same grouping that used to live in the top ShadTabs bar.
    final tabs = <_SettingsTab>[
      _SettingsTab.general,
      if (_showsWindowsTab) _SettingsTab.windows,
      _SettingsTab.about,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      // Two-column layout: vertical group rail on the left, scrolling content
      // on the right. The group rail replaces the former top ShadTabs bar so
      // all settings categories are reachable without horizontal scrolling.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Left sidebar: title + vertical group navigation ---
          SizedBox(
            width: 180,
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
                  '管理远程存储的连接配置、下载目录、界面偏好和挂载行为。',
                  style: TextStyle(
                    color: theme.colorScheme.mutedForeground,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: _buildGroupRail(theme, tabs)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // --- Right content area ---
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._buildActiveContent(theme, config),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
 }

  List<Widget> _buildGeneralSections(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    final sections = <Widget>[
      _buildCard(
        theme,
        '应用更新',
        SettingsUpdateSection(
          theme: theme,
          currentVersion: kAppRuntimeVersion,
          config: config,
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '网络代理',
        SettingsProxySection(
          theme: theme,
         config: config,
          onSaveProxy: (proxyMode, proxyType, proxyHost, proxyPort, proxyUsername, proxyPassword) async {
            await widget.api.updateProxySettings(
              proxyMode: proxyMode,
              proxyType: proxyType,
              proxyHost: proxyHost,
              proxyPort: proxyPort,
              proxyUsername: proxyUsername,
              proxyPassword: proxyPassword,
            );
          },
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(theme, '外观', const ThemePicker()),
      if (widget.api.capabilities.supportsDownloadDirectory) ...[
        const SizedBox(height: 20),
        _buildCard(
          theme,
          '下载设置',
          DownloadDirectorySection(
            theme: theme,
            configuredPath: config.defaultDownloadDirectory,
            saving: _savingDownloadDirectory,
            errorText: _downloadDirectoryError,
            onPickDirectory: () => _pickDownloadDirectory(config),
            onResetDirectory: () => _resetDownloadDirectory(config),
          ),
        ),
      ],
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '缓存设置',
        SettingsCacheSection(
          theme: theme,
          api: widget.api,
          config: config,
          saving: _savingCacheDirectory || _savingCacheRules,
          errorText: _cacheDirectoryError ?? _cacheRulesError,
          stats: _cacheStats,
          loadingStats: _loadingCacheStats,
          cleaning: _cleaningCache,
          opening: _openingCache,
          onPickDirectory: () => _pickCacheDirectory(config),
          onResetDirectory: () => _resetCacheDirectory(config),
          onRefreshStats: () => refreshCacheStats(config),
          onOpenDirectory: () => openCacheDirectory(config),
          onCleanAll: () => cleanCache(config, clearAll: true),
          onCleanRules: () => cleanCache(config, clearAll: false),
          onAutoCleanupChanged: (value) =>
              saveCacheAutoCleanup(config, value),
          onMaxSizeChanged: (value) => saveCacheMaxSize(config, value),
          onMaxAgeChanged: (value) => saveCacheMaxAge(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '显示设置',
        VisibilitySection(
          theme: theme,
          hideDotFiles: config.hideDotFiles,
          saving: _savingVisibility,
          errorText: _visibilityError,
          onChanged: (value) => _saveHideDotFiles(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '同步设置',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WritebackQuietSecondsSection(
              theme: theme,
              seconds: config.writebackQuietSeconds,
              saving: _savingWritebackQuietSeconds,
              errorText: _writebackQuietSecondsError,
              onChanged: (value) => _saveWritebackQuietSeconds(config, value),
            ),
            const SizedBox(height: 20),
            MountMetadataCacheSection(
              theme: theme,
              enabled: config.mountMetadataCacheEnabled,
              seconds: config.effectiveMountMetadataCacheSeconds,
              saving: _savingMountMetadataCache,
              errorText: _mountMetadataCacheError,
              onEnabledChanged: (value) =>
                  _saveMountMetadataCacheEnabled(config, value),
              onSecondsChanged: (value) =>
                  _saveMountMetadataCacheSeconds(config, value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '回收站',
        TrashSettingsSection(
          theme: theme,
          directoryName: config.trashDirectoryName,
          autoCleanupEnabled: config.trashAutoCleanupEnabled,
          retentionDays: config.effectiveTrashRetentionDays,
          saving: _savingTrashSettings,
          errorText: _trashSettingsError,
          onSave: (directoryName, autoCleanupEnabled, retentionDays) =>
              _saveTrashSettings(
                config,
                directoryName,
                autoCleanupEnabled,
                retentionDays,
              ),
        ),
      ),
      const SizedBox(height: 20),
      if (!isWebPlatform) ...[
        _buildCard(
          theme,
          'WebDAV 凭据',
          WebDavCredentialsSection(
            theme: theme,
            username: config.webdavUsername,
            hasPassword: config.hasWebdavPassword,
            saving: _savingWebdavCredentials,
            errorText: _webdavCredentialsError,
            onSave: (username, password) =>
                _saveWebdavCredentials(config, username, password),
          ),
        ),
        const SizedBox(height: 20),
      ],
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '账号重置',
        SettingsResetUserConfigSection(
          theme: theme,
          busy: _resettingUserConfig,
          errorText: _resetUserConfigError,
          onReset: _resetUserConfig,
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '配置管理',
        Row(
          children: [
            ShadButton(onPressed: widget.onEditConfig, child: const Text('重新配置')),
            const SizedBox(width: 10),
            ShadButton.outline(
              onPressed: widget.onRefresh,
              child: const Text('刷新状态'),
            ),
            if (widget.api.capabilities.supportsSessionLogin) ...[
              const SizedBox(width: 10),
              ShadButton.outline(onPressed: _logout, child: const Text('退出登录')),
            ],
          ],
        ),
      ),
    ];
    return sections;
  }


  List<Widget> _buildWindowsSections(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
      _buildCard(
        theme,
        'Windows 入口',
        WindowsThisPcEntrySection(
          theme: theme,
          enabled: config.windowsThisPcEntryEnabled,
          saving: _savingWindowsThisPcEntry,
          errorText: _windowsThisPcEntryError,
          onChanged: (value) => _saveWindowsThisPcEntry(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        'Windows 写回并发',
        WindowsWritebackConcurrencySection(
          theme: theme,
          concurrency: config.windowsWritebackConcurrency,
          saving: _savingWindowsWritebackConcurrency,
          errorText: _windowsWritebackConcurrencyError,
          onChanged: (value) => _saveWindowsWritebackConcurrency(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        'Windows 挂载恢复',
        WindowsMountRecoverySection(
          theme: theme,
          busy: _resettingWindowsMounts,
          cleaningProcesses: _cleaningStaleWindowsProcesses,
          errorText: _windowsMountResetError,
          onReset: _forceResetWindowsMounts,
          onCleanupProcesses: _cleanupStaleWindowsProcesses,
        ),
      ),
    ];
  }

  List<Widget> _buildAboutSections(ShadThemeData theme) {
    return [
      _buildCard(
        theme,
        '关于云卷',
        SettingsAboutSection(theme: theme, versionText: kAppRuntimeVersion),
      ),
    ];
  }

 Widget _buildCard(ShadThemeData theme, String title, Widget child) {
    return SizedBox(
      width: double.infinity,
      child: ShadCard(
     padding: const EdgeInsets.all(20),
     title: Text(
       title,
       style: TextStyle(
         fontWeight: FontWeight.w600,
         fontSize: 14,
         color: theme.colorScheme.foreground,
       ),
     ),
     child: child,
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

  Future<void> _pickCacheDirectory(RemoteStorageConfig config) async {
    final initialDirectory = config.resolvedCacheDirectory.trim().isNotEmpty
        ? config.resolvedCacheDirectory.trim()
        : null;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择缓存目录',
      initialDirectory: initialDirectory,
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    await _saveCacheDirectory(config, path.trim());
  }

  Future<void> _resetCacheDirectory(RemoteStorageConfig config) async {
    await _saveCacheDirectory(config, '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load cache stats once the page is mounted so the card shows real usage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshCacheStats(widget.state.config);
    });
  }
}
