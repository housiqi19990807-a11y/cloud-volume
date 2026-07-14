// 账号代理设置区。默认跟随全局；也可选跟随系统、直连或自定义代理。
// 自定义模式展开 HTTP/SOCKS5、地址、端口与可选认证字段。

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const kAccountProxyModeInherit = 'inherit';
const kAccountProxyModeSystem = 'system';
const kAccountProxyModeDirect = 'direct';
const kAccountProxyModeCustom = 'custom';

class AccountProxySection extends StatefulWidget {
  const AccountProxySection({
    super.key,
    required this.initialMode,
    required this.initialType,
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.passwordController,
    required this.onModeChanged,
    required this.onTypeChanged,
  });

  final String initialMode;
  final String initialType;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onTypeChanged;

  @override
  State<AccountProxySection> createState() => _AccountProxySectionState();
}

class _AccountProxySectionState extends State<AccountProxySection> {
  late String _mode;
  late String _type;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _mode = _normalizeMode(widget.initialMode);
    _type = widget.initialType == 'socks5' ? 'socks5' : 'http';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CloudStorageLabeledField(label: '代理设置', child: _buildModeSelect()),
        const SizedBox(height: 8),
        Text(
          '默认跟随设置中的全局代理；也可为此账号单独指定。',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (_mode == kAccountProxyModeCustom) ...[
          const SizedBox(height: 14),
          _buildCustomFields(theme),
        ],
      ],
    );
  }

  Widget _buildModeSelect() {
    return ShadSelect<String>(
      key: ValueKey('account-proxy-mode-$_mode'),
      initialValue: _mode,
      selectedOptionBuilder: (context, value) => Text(_modeLabel(value)),
      options: const [
        ShadOption(value: kAccountProxyModeInherit, child: Text('使用全局设置')),
        ShadOption(value: kAccountProxyModeSystem, child: Text('使用系统代理')),
        ShadOption(value: kAccountProxyModeDirect, child: Text('直连（不使用代理）')),
        ShadOption(value: kAccountProxyModeCustom, child: Text('自定义代理')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _mode = value);
        widget.onModeChanged(value);
      },
    );
  }

  Widget _buildCustomFields(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              child: CloudStorageLabeledField(
                label: '代理地址',
                child: ShadInput(
                  controller: widget.hostController,
                  placeholder: const Text('127.0.0.1'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CloudStorageLabeledField(
                label: '端口',
                child: ShadInput(
                  controller: widget.portController,
                  placeholder: const Text('7890'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CloudStorageLabeledField(
                label: '代理账号（可选）',
                child: ShadInput(
                  controller: widget.usernameController,
                  placeholder: const Text('username'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CloudStorageLabeledField(
                label: '代理密码（可选）',
                child: Row(
                  children: [
                    Expanded(
                      child: ShadInput(
                        controller: widget.passwordController,
                        obscureText: _obscurePassword,
                        placeholder: const Text('password'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ShadButton.outline(
                      width: 36,
                      height: 36,
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      child: Icon(
                        _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                        size: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _typeChip(ShadThemeData theme, String label, String value) {
    final selected = _type == value;
    return ShadButton.outline(
      onPressed: () {
        setState(() => _type = value);
        widget.onTypeChanged(value);
      },
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

  String _normalizeMode(String value) {
    switch (value.trim()) {
      case kAccountProxyModeSystem:
      case kAccountProxyModeDirect:
      case kAccountProxyModeCustom:
        return value.trim();
      default:
        return kAccountProxyModeInherit;
    }
  }

  String _modeLabel(String value) {
    switch (value) {
      case kAccountProxyModeSystem:
        return '使用系统代理';
      case kAccountProxyModeDirect:
        return '直连（不使用代理）';
      case kAccountProxyModeCustom:
        return '自定义代理';
      default:
        return '使用全局设置';
    }
  }
}
