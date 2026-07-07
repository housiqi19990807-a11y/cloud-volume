part of 'settings_page.dart';

// Per-anchor content builders. Each method returns the card widgets for one
// settings section; the layout file stitches them into one long scroll page.

extension _SettingsSections on _SettingsPageState {
  // ---- General group ----

  List<Widget> _buildUpdateSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
      _buildCard(
        theme,
        '应用更新',
        SettingsUpdateSection(
          theme: theme,
          currentVersion: kAppRuntimeVersion,
          config: config,
          api: widget.api,
        ),
      ),
    ];
  }

  List<Widget> _buildProxySection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
      _buildCard(
        theme,
        '网络代理',
        SettingsProxySection(
          theme: theme,
          config: config,
          onSaveProxy:
              (
                proxyMode,
                proxyType,
                proxyHost,
                proxyPort,
                proxyUsername,
                proxyPassword,
              ) async {
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
    ];
  }

  List<Widget> _buildAppearanceSection(ShadThemeData theme) {
    return [_buildCard(theme, '外观', const ThemePicker())];
  }

  List<Widget> _buildLogSection(ShadThemeData theme) {
    return [_buildCard(theme, '日志设置', SettingsLogSection(theme: theme))];
  }

  List<Widget> _buildDownloadSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
    ];
  }

  List<Widget> _buildCacheSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
          onAutoCleanupChanged: (value) => saveCacheAutoCleanup(config, value),
          onMaxSizeChanged: (value) => saveCacheMaxSize(config, value),
          onMaxAgeChanged: (value) => saveCacheMaxAge(config, value),
        ),
      ),
    ];
  }

  List<Widget> _buildVisibilitySection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
    ];
  }

  List<Widget> _buildSyncSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
    ];
  }

  List<Widget> _buildTrashSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
    ];
  }

  List<Widget> _buildWebdavSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
    ];
  }

  List<Widget> _buildResetAccountSection(ShadThemeData theme) {
    return [
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
    ];
  }

  List<Widget> _buildConfigManageSection(ShadThemeData theme) {
    return [
      _buildCard(
        theme,
        '配置管理',
        Row(
          children: [
            ShadButton(
              onPressed: widget.onEditConfig,
              child: const Text('重新配置'),
            ),
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
  }

  // ---- Windows group ----

  List<Widget> _buildWindowsEntrySection(
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
    ];
  }

  List<Widget> _buildWindowsWritebackSection(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
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
    ];
  }

  List<Widget> _buildWindowsMountSection(ShadThemeData theme) {
    return [
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

  // ---- About group ----

  List<Widget> _buildAboutSection(ShadThemeData theme) {
    return [
      _buildCard(
        theme,
        '关于云卷',
        SettingsAboutSection(theme: theme, versionText: kAppRuntimeVersion),
      ),
    ];
  }
}
