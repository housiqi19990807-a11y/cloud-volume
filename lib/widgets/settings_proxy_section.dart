// 代理设置区：全局代理模式选择（跟随环境变量 / 直连 / 自定义代理）+ GitHub 镜像。
// 自定义代理支持 HTTP / SOCKS5 类型、主机端口、可选账号密码。

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
  final Future<void> Function(RemoteStorageConfig config) onSaveProxy;

  @override
  State<SettingsProxySection> createState() => _SettingsProxySectionState();
}

class _SettingsProxySectionState extends State<SettingsProxySection> {
  late String _proxyMode;
  late String _proxyType;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _mirrorController;
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _proxyMode = c.proxyMode;
    _proxyType = c.proxyType.isEmpty ? 'http' : c.proxyType;
    _hostController = TextEditingController(text: c.proxyHost);
    _portController = TextEditingController(text: c.proxyPort);
    _usernameController = TextEditingController(text: c.proxyUsername);
    _passwordController = TextEditingController(text: c.proxyPassword);
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
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
          const SizedBox(height: 12),
          _buildCustomProxyFields(theme),
        ],
        const SizedBox(height: 14),
        _buildMirrorInput(theme),
        const SizedBox(height: 14),
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

  Widget _buildCustomProxyFields(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Proxy type selector
        Wrap(
          spacing: 8,
          children: [
            _typeChip(theme, 'HTTP', 'http'),
            _typeChip(theme, 'SOCKS5', 'socks5'),
          ],
        ),
        const SizedBox(height: 10),
        // Host + Port row
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _labeledInput(
                theme,
                controller: _hostController,
                label: '代理地址',
                placeholder: '127.0.0.1',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 1,
              child: _labeledInput(
                theme,
                controller: _portController,
                label: '端口',
                placeholder: '7890',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Username + Password row
        Row(
          children: [
            Expanded(
              child: _labeledInput(
                theme,
                controller: _usernameController,
                label: '账号（可选）',
                placeholder: 'username',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _labeledPasswordInput(theme),
            ),
          ],
        ),
      ],
    );
  }

  Widget _typeChip(ShadThemeData theme, String label, String value) {
    final selected = _proxyType == value;
    return ShadButton.outline(
      onPressed: () => setState(() => _proxyType = value),
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

  Widget _labeledInput(
    ShadThemeData theme, {
    required TextEditingController controller,
    required String label,
    required String placeholder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: theme.colorScheme.mutedForeground),
        ),
        const SizedBox(height: 4),
        ShadInput(
          controller: controller,
          placeholder: Text(placeholder),
          style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
        ),
      ],
    );
  }

  Widget _labeledPasswordInput(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '密码（可选）',
          style: TextStyle(fontSize: 11.5, color: theme.colorScheme.mutedForeground),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ShadInput(
                controller: _passwordController,
                placeholder: const Text('password'),
                style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
                obscureText: _obscurePassword,
              ),
            ),
            const SizedBox(width: 4),
            ShadButton.outline(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              width: 36,
              height: 36,
              padding: EdgeInsets.zero,
              child: Icon(
                _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 15,
              ),
            ),
          ],
        ),
      ],
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
      final newConfig = widget.config.copyWith(
        proxyMode: _proxyMode,
        proxyType: _proxyType,
        proxyHost: _hostController.text.trim(),
        proxyPort: _portController.text.trim(),
        proxyUsername: _usernameController.text.trim(),
        proxyPassword: _passwordController.text,
      );
      await widget.onSaveProxy(newConfig);
      await saveUpdateNetworkConfig(
        UpdateNetworkConfig(mirrorPrefix: _mirrorController.text.trim()),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
