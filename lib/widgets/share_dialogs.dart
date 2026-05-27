// Share dialogs cover duration input plus copy-friendly link confirmation flows.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<int?> showShareDurationDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String confirmLabel,
  int initialHours = 24,
}) async {
  final controller = TextEditingController(text: initialHours.toString());
  String? errorText;
  try {
    return await showShadDialog<int?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => ShadDialog(
          title: Text(title),
          description: Text(description),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text('有效时长（小时）'),
                const SizedBox(height: 8),
                ShadInput(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  placeholder: const Text('1 - 168'),
                ),
                const SizedBox(height: 8),
                Text(
                  '支持 1 到 168 小时，分享链接使用预签名下载地址生成。',
                  style: TextStyle(
                    fontSize: 12,
                    color: ShadTheme.of(context).colorScheme.mutedForeground,
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
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
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    ShadButton(
                      onPressed: () {
                        final hours = int.tryParse(controller.text.trim());
                        if (hours == null || hours < 1 || hours > 168) {
                          setDialogState(
                            () => errorText = '请输入 1 到 168 之间的小时数',
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(hours * 3600);
                      },
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<void> showShareLinkDialog(
  BuildContext context, {
  required ShareRecord record,
}) async {
  await showShadDialog<void>(
    context: context,
    builder: (dialogContext) => ShadDialog(
      title: const Text('分享已创建'),
      description: Text('可以直接复制下面的分享链接。'),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              record.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ShadTheme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                record.url,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '有效至 ${_formatDateTime(record.expiresAtDateTime)}',
              style: TextStyle(
                fontSize: 12,
                color: ShadTheme.of(context).colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
                const SizedBox(width: 10),
                ShadButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: record.url));
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('分享链接已复制')));
                  },
                  child: const Text('复制链接'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> showDeleteShareRecordDialog(
  BuildContext context,
  ShareRecord record,
) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('删除分享记录'),
          description: const Text('只会删除本地分享记录，不会删除远程文件。'),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  record.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.destructive(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('删除记录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '--';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
