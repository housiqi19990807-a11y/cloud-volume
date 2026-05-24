// 右侧表单面板：包含 S3 连接字段、认证信息和保存操作。
// 背景延伸至标题栏区域，内容在红绿灯安全区下方开始。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 表单区块标题，用于分组字段。
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
          padding: const EdgeInsets.only(bottom: 5),
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
    required this.bucketController,
    required this.accessKeyController,
    required this.secretKeyController,
    required this.prefixController,
    required this.usePathStyle,
    required this.onPathStyleChanged,
    required this.isSaving,
    required this.errorText,
    required this.onSave,
  });

  final TextEditingController endpointController;
  final TextEditingController regionController;
  final TextEditingController bucketController;
  final TextEditingController accessKeyController;
  final TextEditingController secretKeyController;
  final TextEditingController prefixController;
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
      child: SingleChildScrollView(
        // top: 40 matches left panel traffic-light safe zone
        padding: const EdgeInsets.only(
          left: 40,
          right: 40,
          top: 40,
          bottom: 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '初始化配置',
              style: theme.textTheme.h3.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '配置 S3 兼容存储的连接信息。',
              style: theme.textTheme.muted.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 32),

            // 连接配置
            const SectionLabel('连接配置'),
            const SizedBox(height: 10),
            FormFieldRow(
              label: '端点地址',
              child: ShadInput(
                controller: endpointController,
                placeholder: const Text('https://s3.example.com'),
              ),
            ),
            const SizedBox(height: 14),
            FormFieldRow(
              label: '区域',
              child: ShadInput(
                controller: regionController,
                placeholder: const Text('auto / us-east-1'),
              ),
            ),
            const SizedBox(height: 14),
            FormFieldRow(
              label: '存储桶',
              child: ShadInput(
                controller: bucketController,
                placeholder: const Text('media-assets'),
              ),
            ),
            const SizedBox(height: 14),
            FormFieldRow(
              label: '根前缀',
              child: ShadInput(
                controller: prefixController,
                placeholder: const Text('library/music'),
              ),
            ),

            const SizedBox(height: 28),

            // 认证信息
            const SectionLabel('认证信息'),
            const SizedBox(height: 10),
            FormFieldRow(
              label: '访问密钥 ID',
              child: ShadInput(
                controller: accessKeyController,
                placeholder: const Text('AKIA...'),
              ),
            ),
            const SizedBox(height: 14),
            FormFieldRow(
              label: '访问密钥',
              child: ShadInput(
                controller: secretKeyController,
                placeholder: const Text('请输入密钥'),
                obscureText: true,
              ),
            ),

            const SizedBox(height: 28),

            // 选项
            const SectionLabel('选项'),
            const SizedBox(height: 10),
            ShadSwitch(
              value: usePathStyle,
              onChanged: isSaving ? null : onPathStyleChanged,
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

            if (errorText != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.destructive.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.destructive.withValues(alpha: 0.2),
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

            const SizedBox(height: 32),
            ShadButton(
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
