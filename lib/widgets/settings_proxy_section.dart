// 代理设置区：下拉选择跟随系统 / 直连 / 自定义。
// 跟随系统、直连切换后自动保存；仅自定义时展示表单与「保存代理设置」。
// GitHub 加速镜像不在这里，在「应用更新」区域单独配置。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _kProxyModeSystem = 'system';
const String _kProxyModeDirect = 'direct';
const String _kProxyModeCustom = 'custom';

const List<({String value, String label})> _kProxyModeOptions = [
  (value: _kProxyModeSystem, label: '跟随系统'),
  (value: _kProxyModeDirect, label: '直连'),
  (value: _kProxyModeCustom, label: '自定义'),
];

class SettingsProxySection extends StatefulWidget {
  const SettingsProxySection({
    super.key,
    required this.theme,
    required this.config,
    required this.onSaveProxy,
  });

  final ShadThemeData theme;
  final RemoteStorageConfig config;
  final Future<void> Function(
    String proxyMode,
    String proxyType,
    String proxyHost,
    String proxyPort,
    String proxyUsername,
    String proxyPassword,
  )
  onSaveProxy;

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
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _applyConfig(widget.config);
    _hostController = TextEditingController(text: widget.config.proxyHost);
    _portController = TextEditingController(text: widget.config.proxyPort);
    _usernameController = TextEditingController(
      text: widget.config.proxyUsername,
    );
    _passwordController = TextEditingController(
      text: widget.config.proxyPassword,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsProxySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.proxyMode != widget.config.proxyMode && !_saving) {
      _applyConfig(widget.config);
    }
  }

  void _applyConfig(RemoteStorageConfig c) {
    _proxyMode = _normalizeMode(c.proxyMode);
    _proxyType = c.proxyType.isEmpty ? 'http' : c.proxyType;
  }

  String _normalizeMode(String mode) {
    final trimmed = mode.trim();
    if (trimmed == _kProxyModeDirect || trimmed == _kProxyModeCustom) {
      return trimmed;
    }
    return _kProxyModeSystem;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '全局代理作为各账号的默认值；每个账号也可在账号管理中单独选择跟随系统、直连或自定义代理。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        _buildProxyModeDropdown(theme),
        if (_proxyMode == _kProxyModeCustom) ...[
          const SizedBox(height: 12),
          _buildCustomProxyFields(theme),
          const SizedBox(height: 14),
          _buildSaveButton(theme),
        ],
      ],
    );
  }

  Widget _buildProxyModeDropdown(ShadThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ShadSelect<String>(
        key: ValueKey<String>('proxy-mode-$_proxyMode'),
        minWidth: 220,
        initialValue: _proxyMode,
        placeholder: Text(_labelForMode(_proxyMode)),
        selectedOptionBuilder: (context, selected) =>
            Text(_labelForMode(selected)),
        options: _kProxyModeOptions
            .map(
              (o) => ShadOption<String>(value: o.value, child: Text(o.label)),
            )
            .toList(growable: false),
        onChanged: _saving
            ? null
            : (value) {
                if (value == null || value == _proxyMode) return;
                setState(() => _proxyMode = value);
                if (value == _kProxyModeSystem || value == _kProxyModeDirect) {
                  unawaited(_savePresetMode(value));
                }
              },
      ),
    );
  }

  String _labelForMode(String mode) {
    for (final o in _kProxyModeOptions) {
      if (o.value == mode) return o.label;
    }
    return _kProxyModeOptions.first.label;
  }

  Widget _buildCustomProxyFields(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _typeChip(theme, 'HTTP', 'http'),
            _typeChip(theme, 'SOCKS5', 'socks5'),
          ],
        ),
        const SizedBox(height: 10),
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
            Expanded(child: _labeledPasswordInput(theme)),
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
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
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
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ShadInput(
                controller: _passwordController,
                placeholder: const Text('password'),
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.foreground,
                ),
                obscureText: _obscurePassword,
              ),
            ),
            const SizedBox(width: 4),
            ShadButton.outline(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              width: 36,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 0),
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

  Widget _buildSaveButton(ShadThemeData theme) {
    return ShadButton(
      onPressed: _saving ? null : _save,
      child: Text(_saving ? '保存中...' : '保存代理设置'),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSaveProxy(
        _proxyMode,
        _proxyType,
        _hostController.text.trim(),
        _portController.text.trim(),
        _usernameController.text.trim(),
        _passwordController.text,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// System/direct only: switch mode and keep stored custom fields in config.
  Future<void> _savePresetMode(String mode) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final c = widget.config;
      await widget.onSaveProxy(
        mode,
        c.proxyType.isEmpty ? 'http' : c.proxyType,
        c.proxyHost,
        c.proxyPort,
        c.proxyUsername,
        c.proxyPassword,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
