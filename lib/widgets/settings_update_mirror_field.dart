// GitHub 加速镜像配置：独立于代理设置，仅影响 GitHub 更新包下载。
// Release 元数据检查走 GitHub API 直连，不受此镜像影响。

import 'package:flutter/material.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
  late TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialConfig.mirrorPrefix);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          ShadInput(
            controller: _controller,
            placeholder: const Text('https://gh-proxy.com'),
            style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _mirrorChip('直连', ''),
              _mirrorChip('gh-proxy', 'https://gh-proxy.com'),
              _mirrorChip('ghfast', 'https://ghfast.top'),
              const SizedBox(width: 8),
              ShadButton(
                onPressed: _saving ? null : _save,
                height: 30,
                child: Text(
                  _saving ? '保存中...' : '保存镜像',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mirrorChip(String label, String value) {
    return ShadButton.outline(
      onPressed: () => _controller.text = value,
      height: 30,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config =
          UpdateNetworkConfig(mirrorPrefix: _controller.text.trim());
      await saveUpdateNetworkConfig(config);
      widget.onSaved(config);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
