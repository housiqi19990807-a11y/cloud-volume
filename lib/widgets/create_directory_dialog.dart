// 新建目录弹窗：负责目录名称输入、创建中状态和错误反馈。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CreateDirectoryDialog extends StatelessWidget {
  const CreateDirectoryDialog({
    super.key,
    required this.controller,
    required this.errorText,
    required this.creating,
    required this.onCancel,
    required this.onCreate,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool creating;
  final VoidCallback onCancel;
  final Future<void> Function() onCreate;

  static Future<void> show(
    BuildContext context, {
    required TextEditingController controller,
    required String? errorText,
    required bool creating,
    required VoidCallback onCancel,
    required Future<void> Function() onCreate,
  }) {
    return showShadDialog(
      context: context,
      builder: (_) => CreateDirectoryDialog(
        controller: controller,
        errorText: errorText,
        creating: creating,
        onCancel: onCancel,
        onCreate: onCreate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('新建目录'),
      description: const Text('输入目录名称后，会在当前路径下创建空目录。'),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
           ShadInput(
             controller: controller,
             placeholder: const Text('例如：images / backup'),
             onSubmitted: creating ? null : (_) => onCreate(),
           ),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                errorText!,
                style: TextStyle(
                  fontSize: 12,
                  color: ShadTheme.of(context).colorScheme.destructive,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: creating ? null : onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                ShadButton(
                  onPressed: creating ? null : onCreate,
                  child: Text(creating ? '创建中...' : '创建'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
