// 代理设置区：全局代理模式选择（跟随环境变量 / 直连 / 自定义代理）+ GitHub 镜像。
// 代理配置写入 Go config（影响 S3/WebDAV/百度网盘所有网络请求），
// 镜像配置写入 SharedPreferences（仅影响 GitHub 更新检查与下载）。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsProxySection extends StatefulWidget {
  const SettingsProxySection({
    super.key,
    required this.theme,
    required this.config,
    required this.onSaveProxy,
  });

  final ShadThemeData theme;
  final RemoteStorageConfig config;
  final void Function(String mode, String proxyUrl) onSaveProxy;

  @override
  State<SettingsProxySection> createState() => _SettingsProxySectionState();
}

class _SettingsProxySectionState extends State<SettingsProxySection> {
  late String _proxyMode;
  late TextEditingController _proxyUrlController;
  late TextEditingController _mirrorController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _proxyMode = widget.config.proxyMode;
    _proxyUrlController = TextEditingController(text: widget.config.proxyUrl);
    _mirrorController = TextEditingController();
    _loadMirror();
  }

  Future<void> _loadMirror() async {
    final config = await loadUpdateNetworkConfig();
    if (mounted) {
      _mirrorController.text = config.mirrorPrefix;
    }
  }

  @override
  void dispose() {
    _proxyUrlController.dispose();
    _mirrorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '代理设置影响应用所有网络请求（S3、WebDAV、百度网盘、GitHub 更新检查）。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        _buildProxyModeSelector(theme),
        if (_proxyMode == 'custom') ...[
          const SizedBox(height: 10),
          _buildProxyUrlInput(theme),
        ],
        const SizedBox(height: 10),
        _buildMirrorInput(theme),
        const SizedBox(height: 12),
        _buildSaveButton(theme),
      ],
    );
  }

  Widget _buildProxyModeSelector(ShadThemeData theme) {
    return Wrap(
      spacing: 8,
      children: [
        _modeChip(theme, '跟随系统', 'system'),
        _modeChip(theme, '直连', 'direct'),
        _modeChip(theme, '自定义', 'custom'),
      ],
    );
  }

  Widget _modeChip(ShadThemeData theme, String label, String value) {
    final selected = _proxyMode == value;
    return ShadButton.outline(
      onPressed: () => setState(() => _proxyMode = value),
      backgroundColor: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,

      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }

  Widget _buildProxyUrlInput(ShadThemeData theme) {
    return ShadInput(
      controller: _proxyUrlController,
      placeholder: const Text('http://127.0.0.1:7890'),
      style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
    );
  }

  Widget _buildMirrorInput(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GitHub 加速镜像（用于更新检查和下载，留空则直连）',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: _mirrorController,
          placeholder: const Text('https://gh-proxy.com'),
          style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            _mirrorChip('直连', ''),
            _mirrorChip('gh-proxy', 'https://gh-proxy.com'),
            _mirrorChip('ghfast', 'https://ghfast.top'),
          ],
        ),
      ],
    );
  }

  Widget _mirrorChip(String label, String value) {
    return ShadButton.outline(
      onPressed: () => _mirrorController.text = value,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _buildSaveButton(ShadThemeData theme) {
    return ShadButton(
      onPressed: _saving ? null : _save,
      child: Text(_saving ? '保存中...' : '保存代理设置'),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      widget.onSaveProxy(_proxyMode, _proxyUrlController.text.trim());
      // Save the mirror setting.
      await saveUpdateNetworkConfig(
        UpdateNetworkConfig(mirrorPrefix: _mirrorController.text.trim()),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
