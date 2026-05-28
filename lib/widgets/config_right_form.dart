// 右侧表单面板：居中卡片式布局，认证字段为主，高级设置通过弹窗配置。
// 标题固定顶部，按钮固定底部，中间字段区可滚动以防溢出。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';

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
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部留白（为 macOS 红绿灯让位）。
              const SizedBox(height: 72),
              // 标题。
              Text(
                '登录远程存储',
                style: theme.textTheme.h3.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.foreground,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '输入你的认证信息以开始使用。',
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // 可滚动表单区。
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 分区标题。
                      _sectionLabel(context, '认证信息'),
                      const SizedBox(height: 16),
                      // 访问密钥 ID。
                      _fieldLabel(context, '访问密钥 ID'),
                      const SizedBox(height: 6),
                      ShadInput(
                        controller: accessKeyController,
                        placeholder: const Text('输入 Access Key ID'),
                      ),
                      const SizedBox(height: 18),
                      // 访问密钥。
                      _fieldLabel(context, '访问密钥'),
                      const SizedBox(height: 6),
                      ShadInput(
                        controller: secretKeyController,
                        placeholder: const Text('输入 Secret Access Key'),
                        obscureText: true,
                      ),
                      // 高级设置入口。
                      const SizedBox(height: 18),
                      _AdvancedSettingsLink(
                        onTap: isSaving
                            ? null
                            : () => _openAdvancedDialog(context),
                      ),
                      // 错误提示。
                      if (errorText != null) ...[
                        const SizedBox(height: 16),
                        _errorBanner(context, errorText!),
                      ],
                    ],
                  ),
                ),
              ),
              // 底部保存按钮。
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 40),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ShadButton(
                    onPressed: isSaving ? null : onSave,
                    child: isSaving
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: AppLoadingIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primaryForeground,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('保存中...'),
                            ],
                          )
                        : const Text(
                            '保存并继续',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.mutedForeground,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.foreground,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.destructive.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.destructive.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 15,
            color: theme.colorScheme.destructive,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.destructive,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开高级设置弹窗。
  void _openAdvancedDialog(BuildContext context) {
    final epCtrl = TextEditingController(text: endpointController.text);
    final rgCtrl = TextEditingController(text: regionController.text);
    var pathStyle = usePathStyle;

    showShadDialog(
      context: context,
      builder: (dialogContext) {
        return ShadDialog(
          title: const Text('高级设置'),
          description: const Text('配置端点地址、区域和连接选项。'),
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final theme = ShadTheme.of(dialogContext);
              return SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    _fieldLabel(dialogContext, '端点地址'),
                    const SizedBox(height: 5),
                    ShadInput(
                      controller: epCtrl,
                      placeholder: const Text('https://s3.example.com'),
                    ),
                    const SizedBox(height: 14),
                    _fieldLabel(dialogContext, '区域'),
                    const SizedBox(height: 5),
                    ShadInput(
                      controller: rgCtrl,
                      placeholder: const Text('auto / us-east-1'),
                    ),
                    const SizedBox(height: 16),
                    ShadSwitch(
                      value: pathStyle,
                      onChanged: (v) => setDialogState(() => pathStyle = v),
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
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ShadButton.outline(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 10),
                        ShadButton(
                          onPressed: () {
                            endpointController.text = epCtrl.text;
                            regionController.text = rgCtrl.text;
                            onPathStyleChanged(pathStyle);
                            Navigator.of(dialogContext).pop();
                          },
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 高级设置文字链接。
class _AdvancedSettingsLink extends StatelessWidget {
  const _AdvancedSettingsLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = theme.colorScheme.primary;
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              '高级设置',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
