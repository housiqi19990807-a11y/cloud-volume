// GitHub 加速镜像配置：独立于代理设置，仅影响 GitHub 更新包下载。
// Release 元数据检查走 GitHub API 直连，不受此镜像影响。
// 交互上采用“选择模式”：直连 / 常用镜像 / 自定义；只有自定义时才需要填写地址。

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:remote_storage/services/app_update_service.dart';
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
  // 镜像探测按钮状态：null=空闲，true=可用，false=不可用，短文案显示在按钮旁。
  bool? _probeOk;
  bool _probing = false;
  String _probeMessage = '';

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
  void didUpdateWidget(covariant SettingsUpdateMirrorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级 `_loadMirrorConfig` 是异步的：首次构建时 initialConfig 为空，
    // 读取完成后会带着真实镜像前缀重建本组件。若不在这里重新解析
    // _mode，UI 会一直停留在“直连”，导致每次启动镜像都显示错。
    final prefix = widget.initialConfig.mirrorPrefix;
    if (prefix != oldWidget.initialConfig.mirrorPrefix) {
      final newMode = _resolveMode(prefix);
      if (newMode != _mode) {
        _mode = newMode;
        if (newMode == _kModeCustom) _controller.text = prefix;
        // 清空上一次探测结果，避免文案与新选中镜像不匹配。
        _probeOk = null;
        _probeMessage = '';
      }
    }
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
          const SizedBox(height: 10),
          _buildProbeButton(theme),
        ],
      ),
    );
  }

  Widget _buildProbeButton(ShadThemeData theme) {
    final hasTarget = _currentMirrorPrefix().isNotEmpty;
    return Row(
      children: [
        ShadButton.outline(
          onPressed: (_probing || !hasTarget) ? null : _probeMirror,
          height: 30,
          child: Text(
            _probing ? '测试中...' : '测试镜像可用性',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (_probeMessage.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _probeMessage,
              style: TextStyle(
                fontSize: 11.5,
                color: _probeOk == true
                    ? theme.colorScheme.primary
                    : theme.colorScheme.destructive,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 返回当前选中模式下应使用的镜像前缀；直连返回空。自定义模式取输入框文本。
  String _currentMirrorPrefix() {
    if (_mode == _kModeCustom) return _controller.text.trim();
    return _kOptions.firstWhere(
      (o) => o.mode == _mode,
      orElse: () => _kOptions.first,
    ).value;
  }

  /// 对当前选中的镜像做一次 HEAD 探测。用 GitHub 最新 Release 的第一个 asset
  /// 作为真实下载 URL，包裹镜像前缀后请求，2xx 视为可用。
  Future<void> _probeMirror() async {
    final prefix = _currentMirrorPrefix();
    if (prefix.isEmpty) {
      setState(() {
        _probeOk = null;
        _probeMessage = '当前为直连，无需测试镜像。';
      });
      return;
    }
    setState(() {
      _probing = true;
      _probeMessage = '正在测试镜像...';
    });
    try {
      // 先直连 GitHub API 拿到一个真实 asset 的 download URL。
      final apiResponse = await http
          .get(Uri.parse(kAppLatestReleaseApiUrl),
              headers: const {'accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 30));
      if (apiResponse.statusCode < 200 || apiResponse.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _probing = false;
          _probeOk = false;
          _probeMessage =
              '获取 GitHub Release 失败 (HTTP ${apiResponse.statusCode})。';
        });
        return;
      }
      final payload = jsonDecode(apiResponse.body) as Map<String, dynamic>;
      final rawAssets = payload['assets'];
      String? sampleUrl;
      if (rawAssets is List) {
        for (final asset in rawAssets) {
          if (asset is Map<String, dynamic>) {
            final url = asset['browser_download_url']?.toString();
            if (url != null && url.isNotEmpty) {
              sampleUrl = url;
              break;
            }
          }
        }
      }
      if (sampleUrl == null) {
        if (!mounted) return;
        setState(() {
          _probing = false;
          _probeOk = false;
          _probeMessage = '当前 Release 没有可下载的 asset。';
        });
        return;
      }
      final wrapped =
          UpdateNetworkConfig(mirrorPrefix: prefix).wrapUrl(sampleUrl);
      final probeResp =
          await http.head(Uri.parse(wrapped)).timeout(const Duration(seconds: 20));
      final ok = probeResp.statusCode >= 200 && probeResp.statusCode < 300;
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeOk = ok;
        _probeMessage = ok
            ? '镜像可用 (HTTP ${probeResp.statusCode})。'
            : '镜像返回 HTTP ${probeResp.statusCode}，可能不支持大文件下载。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeOk = false;
        final text = error.toString();
        _probeMessage = text.contains('TimeoutException')
            ? '镜像探测超时，该镜像可能不可用或较慢。'
            : '镜像探测失败：$text';
      });
    }
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
    setState(() {
      _mode = option.mode;
      _probeOk = null;
      _probeMessage = '';
    });
    if (option.mode != _kModeCustom) {
      await _save(option.value);
    }
  }

  Future<void> _saveCustom() async {
    setState(() {
      _probeOk = null;
      _probeMessage = '';
    });
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
