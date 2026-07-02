// GitHub 加速镜像配置：独立于代理设置，仅影响 GitHub 更新包下载。
// Release 元数据检查走 GitHub API 直连，不受此镜像影响。
// 交互上采用“选择模式”：直连 / 常用镜像 / 自定义；只有自定义时才需要填写地址。

import 'package:flutter/material.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _kModeDirect = 'direct';
const String _kModeGhProxy = 'gh-proxy';
const String _kModeGhFast = 'ghfast';
const String _kModeCustom = 'custom';

class _MirrorOption {
  const _MirrorOption({
    required this.mode,
    required this.label,
    required this.value,
  });

  final String mode;
  final String label;
  final String value;
}

const List<_MirrorOption> _kOptions = [
  _MirrorOption(mode: _kModeDirect, label: '直连', value: ''),
  _MirrorOption(mode: _kModeGhProxy, label: 'gh-proxy', value: 'https://gh-proxy.com'),
  _MirrorOption(mode: _kModeGhFast, label: 'ghfast', value: 'https://ghfast.top'),
  _MirrorOption(mode: _kModeCustom, label: '自定义', value: ''),
];

class SettingsUpdateMirrorField extends StatefulWidget {
  const SettingsUpdateMirrorField({
    super.key,
    required this.theme,
    required this.initialConfig,
    required this.onSaved,
  });

  final ShadThemeData theme;
  final UpdateNetworkConfig initialConfig;
  final void Function(UpdateNetworkConfig config) onSaved;

  @override
  State<SettingsUpdateMirrorField> createState() =>
      _SettingsUpdateMirrorFieldState();
}

class _SettingsUpdateMirrorFieldState extends State<SettingsUpdateMirrorField> {
  late String _mode;
  late TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialPrefix = widget.initialConfig.mirrorPrefix;
    _mode = _resolveMode(initialPrefix);
    // 自定义模式下保留用户输入；非自定义时输入框不展示，控制器内容无意义。
    _controller = TextEditingController(
      text: _mode == _kModeCustom ? initialPrefix : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 根据已保存的镜像前缀推断当前应高亮的选项。
  String _resolveMode(String prefix) {
    if (prefix.isEmpty) return _kModeDirect;
    final trimmed = prefix.trim();
    if (trimmed == 'https://gh-proxy.com') return _kModeGhProxy;
    if (trimmed == 'https://ghfast.top') return _kModeGhFast;
    return _kModeCustom;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GitHub 下载加速镜像',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '仅加速安装包下载；版本检查直连 GitHub API，留空则全程直连。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kOptions.map((option) => _buildOptionChip(theme, option)).toList(),
          ),
          if (_mode == _kModeCustom) ...[
            const SizedBox(height: 10),
            _buildCustomInput(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionChip(ShadThemeData theme, _MirrorOption option) {
    final selected = _mode == option.mode;
    return ShadButton.outline(
      onPressed: _saving ? null : () => _selectOption(option),
      backgroundColor: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
      height: 32,
      child: Text(
        option.label,
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

  Widget _buildCustomInput(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadInput(
          controller: _controller,
          placeholder: const Text('https://example.com'),
          style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
        ),
        const SizedBox(height: 8),
        ShadButton(
          onPressed: _saving ? null : _saveCustom,
          height: 30,
          child: Text(
            _saving ? '保存中...' : '保存自定义镜像',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _selectOption(_MirrorOption option) async {
    if (_mode == option.mode) return;
    setState(() => _mode = option.mode);
    if (option.mode != _kModeCustom) {
      await _save(option.value);
    }
  }

  Future<void> _saveCustom() async {
    await _save(_controller.text.trim());
  }

  Future<void> _save(String prefix) async {
    setState(() => _saving = true);
    try {
      final config = UpdateNetworkConfig(mirrorPrefix: prefix);
      await saveUpdateNetworkConfig(config);
      widget.onSaved(config);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
