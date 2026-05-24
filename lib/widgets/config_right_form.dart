// 右侧表单面板：认证字段为主，高级设置可折叠。
// 标题固定顶部，按钮固定底部，中间字段区可滚动以防溢出。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 表单区块标题。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: theme.textTheme.small.copyWith(
        color: theme.colorScheme.mutedForeground,
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// 标签 + 字段行。
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.foreground,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 配置页右侧完整表单。
class ConfigRightFormPanel extends StatelessWidget {
  const ConfigRightFormPanel({
    super.key,
    required this.endpointController,
    required this.regionController,
    required this.accessKeyController,
    required this.secretKeyController,
    required this.usePathStyle,
    required this.onPathStyleChanged,
    required this.isSaving,
    required this.errorText,
    required this.onSave,
  });

  final TextEditingController endpointController;
  final TextEditingController regionController;
  final TextEditingController accessKeyController;
  final TextEditingController secretKeyController;
  final bool usePathStyle;
  final ValueChanged<bool> onPathStyleChanged;
  final bool isSaving;
  final String? errorText;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      color: theme.colorScheme.background,
      padding: const EdgeInsets.only(left: 40, right: 40, top: 48, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed header.
          Text(
            '初始化配置',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '配置远程存储的连接信息。',
            style: theme.textTheme.muted.copyWith(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),

          // Scrollable fields.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main: auth fields.
                  const SectionLabel('认证信息'),
                  const SizedBox(height: 8),
                  FormFieldRow(
                    label: '访问密钥 ID',
                    child: ShadInput(
                      controller: accessKeyController,
                      placeholder: const Text('AKIA...'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FormFieldRow(
                    label: '访问密钥',
                    child: ShadInput(
                      controller: secretKeyController,
                      placeholder: const Text('请输入密钥'),
                      obscureText: true,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Collapsible advanced settings.
                  _AdvancedSettings(
                    endpointController: endpointController,
                    regionController: regionController,
                    usePathStyle: usePathStyle,
                    onPathStyleChanged: onPathStyleChanged,
                  ),

                  if (errorText != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.destructive.withValues(
                          alpha: 0.06,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.destructive.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: theme.colorScheme.destructive,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorText!,
                              style: TextStyle(
                                color: theme.colorScheme.destructive,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Fixed bottom button.
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              onPressed: isSaving ? null : onSave,
              child: isSaving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primaryForeground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('保存中...'),
                      ],
                    )
                  : const Text('保存并继续'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible section for endpoint, region, and path-style toggle.
class _AdvancedSettings extends StatefulWidget {
  const _AdvancedSettings({
    required this.endpointController,
    required this.regionController,
    required this.usePathStyle,
    required this.onPathStyleChanged,
  });

  final TextEditingController endpointController;
  final TextEditingController regionController;
  final bool usePathStyle;
  final ValueChanged<bool> onPathStyleChanged;

  @override
  State<_AdvancedSettings> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<_AdvancedSettings> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 4),
              Text(
                '高级设置',
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          FormFieldRow(
            label: '端点地址',
            child: ShadInput(
              controller: widget.endpointController,
              placeholder: const Text('https://s3.example.com'),
            ),
          ),
          const SizedBox(height: 12),
          FormFieldRow(
            label: '区域',
            child: ShadInput(
              controller: widget.regionController,
              placeholder: const Text('auto / us-east-1'),
            ),
          ),
          const SizedBox(height: 12),
          ShadSwitch(
            value: widget.usePathStyle,
            onChanged: widget.onPathStyleChanged,
            label: Text(
              '使用路径风格访问',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
            sublabel: Text(
              '推荐用于大多数 S3 兼容及私有对象存储。',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
