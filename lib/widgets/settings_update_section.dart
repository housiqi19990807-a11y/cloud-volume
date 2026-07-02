// 更新检查区：在通用设置中展示版本状态，并提供 GitHub 下载页入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/services/app_installer.dart';
import 'package:remote_storage/services/app_update_service.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/services/proxy_http_client.dart';
import 'package:remote_storage/services/platform_asset_matcher.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/settings_update_mirror_field.dart'
   show SettingsUpdateMirrorField;
import 'package:remote_storage/widgets/update_status_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsUpdateSection extends StatefulWidget {
  const SettingsUpdateSection({
    super.key,
    required this.theme,
    required this.currentVersion,
    this.config,
    this.updateService,
    this.api,
  });

  final ShadThemeData theme;
  final String currentVersion;
  final RemoteStorageConfig? config;
  final AppUpdateService? updateService;
  final RemoteStorageGateway? api;

  @override
  State<SettingsUpdateSection> createState() => _SettingsUpdateSectionState();
}

class _SettingsUpdateSectionState extends State<SettingsUpdateSection> {
  late final AppUpdateService _updateService;
  late final bool _ownsUpdateService;
  AppUpdateCheckResult? _result;
  String? _errorText;
  bool _checking = false;
  bool _openingDownloadPage = false;
  bool _installing = false;
  double _installProgress = 0; // 0..1
  String _installStatusText = '';
  UpdateNetworkConfig _mirrorConfig = const UpdateNetworkConfig();
  // Compile-time architecture reported by the Go bridge; empty until loaded.
  String _buildArch = '';

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? AppUpdateService();
    _ownsUpdateService = widget.updateService == null;
    _loadMirrorConfig();
    _loadBuildArch();
  }

  /// Prefer the architecture injected into the Go bridge at build time. Falls
  /// back to a runtime heuristic when the bridge is unavailable (web, dev).
  Future<void> _loadBuildArch() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final info = await api.getBuildInfo();
      final arch = info.buildArch.isNotEmpty ? info.buildArch : info.runtimeArch;
      if (!mounted) return;
      if (arch.isNotEmpty) setState(() => _buildArch = arch);
    } catch (_) {
      // Non-fatal: matchPlatformAsset falls back to runtime detection.
    }
  }

  Future<void> _loadMirrorConfig() async {
    final config = await loadUpdateNetworkConfig();
    if (!mounted) return;
    setState(() => _mirrorConfig = config);
  }

  @override
  void dispose() {
    if (_ownsUpdateService) {
      _updateService.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UpdateStatusRow(
         theme: theme,
         title: _statusTitle,
         subtitle: _statusSubtitle,
        highlighted: _result?.updateAvailable == true,
        errorText: _errorText,
        checking: _checking,
        openingDownloadPage: _openingDownloadPage,
         installing: _installing,
     installProgress: _installProgress,
         canInstallInApp: _canInstallInApp,
        onCheckForUpdates: _checking ? null : _checkForUpdates,
        onOpenDownloadPage: _openingDownloadPage ? null : _openDownloadPage,
       onInstall: (_installing || !_canInstallInApp) ? null : _startInstall,
     ),
        const SizedBox(height: 14),
        SettingsUpdateMirrorField(
          theme: theme,
          initialConfig: _mirrorConfig,
          onSaved: (config) {
            setState(() => _mirrorConfig = config);
          },
        ),
     ],
    );
  }

  /// Whether the current release has a platform-matched asset for auto-install.
  bool get _canInstallInApp {
    final result = _result;
    if (result == null || !result.updateAvailable) return false;
    if (!kSupportsInAppInstall) return false;
    return matchPlatformAsset(
          result.assets,
          runtimeArchitecture: _buildArch,
        ) !=
        null;
  }

  ProxyConfig get _proxyConfig => ProxyConfig(
    mode: widget.config?.proxyMode ?? kProxyModeSystem,
    type: widget.config?.proxyType ?? kProxyTypeHttp,
    host: widget.config?.proxyHost ?? '',
    port: widget.config?.proxyPort ?? '',
    username: widget.config?.proxyUsername ?? '',
    password: widget.config?.proxyPassword ?? '',
  );

  /// Full download + install + relaunch flow.
  Future<void> _startInstall() async {
    final result = _result;
    if (result == null) return;
    final matched = matchPlatformAsset(
      result.assets,
      runtimeArchitecture: _buildArch,
    );
    if (matched == null) {
      _showError('未找到适合当前平台的安装包，请前往 GitHub 手动下载。');
      return;
    }

    setState(() {
      _installing = true;
      _installProgress = -1;
      _installStatusText = '正在下载 ${matched.asset.name}...';
      _errorText = null;
    });

    final error = await downloadAndInstallAsset(
      matched.asset,
      matched.installerType,
      networkConfig: _mirrorConfig,
      proxyConfig: _proxyConfig,
      onProgress: (received, total) {
        if (!mounted) return;
        final progress = total > 0 ? received / total : -1.0;
        setState(() {
          _installProgress = progress;
          if (progress >= 1) {
            _installStatusText = '下载完成，正在安装...';
          } else if (progress < 0) {
            _installStatusText = '正在下载 ${_formatBytes(received)}...';
          }
        });
      },
    );

    // On success the installer calls exit(0) after relaunching, so reaching
    // here means something went wrong.
    if (!mounted) return;
    // The installer exits on success; reaching here means it failed.
   _resetInstallState();
    // ignore: invalid_null_aware_operator
    final hasError = error?.isNotEmpty == true;
    _showError(
      // ignore: unnecessary_non_null_assertion
      hasError ? error! : '更新未完成，请重试或前往 GitHub 手动下载。',
    );
}

  void _resetInstallState() {
    _installing = false;
    _installProgress = 0;
    _installStatusText = '';
  }

  String get _statusTitle {
    final result = _result;
    if (_checking) {
      return '正在连接 GitHub';
    }
    if (_installing) {
      if (_installProgress < 0) {
        return '正在下载安装包';
      }
      final pct = (_installProgress * 100).clamp(0, 100).toInt();
      return _installProgress >= 1 ? '正在安装新版本...' : '正在下载 $pct%';
    }
    if (result == null) {
      return '当前版本 ${widget.currentVersion}';
    }
    if (!result.comparable) {
      return '最新发布版本 ${result.latestVersion}';
    }
    if (result.updateAvailable) {
      return '发现新版本 ${result.latestVersion}';
    }
    return '当前已是最新版本';
  }

  String get _statusSubtitle {
    final result = _result;
    if (_checking) {
      return '正在读取 GitHub 最新 Release 信息。';
    }
    if (_installing) {
      return _installStatusText.isEmpty
          ? '请稍候，更新过程中应用将自动重启。'
          : _installStatusText;
    }
    if (result == null) {
      return '检测 GitHub Release 是否有可用的新版本，也可以直接打开下载页。';
    }
    if (!result.comparable) {
      return '本地版本 ${result.currentVersion} 无法自动比较，可打开下载页查看是否需要更新。';
    }
    if (result.updateAvailable) {
      return '本地版本 ${result.currentVersion}，可前往 GitHub Release 下载更新。';
    }
    return '本地版本 ${result.currentVersion}，GitHub 最新发布版本 ${result.latestVersion}。';
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _errorText = null;
    });
    try {
     final result = await _updateService.checkLatestRelease(
        currentVersion: widget.currentVersion,
        networkConfig: _mirrorConfig,
        proxyConfig: _proxyConfig,
      );
      if (!mounted) {
        return;
      }
      setState(() => _result = result);
    } on TimeoutException {
      _showError('连接 GitHub 超时，请稍后重试。');
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _openDownloadPage() async {
    setState(() {
      _openingDownloadPage = true;
      _errorText = null;
    });
    try {
      final target = _result?.releaseUrl ?? kAppLatestReleasePageUrl;
      final launched = await launchUrl(
        Uri.parse(target),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!launched) {
        _showError('无法打开 GitHub 下载页。');
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _openingDownloadPage = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _errorText = message);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
