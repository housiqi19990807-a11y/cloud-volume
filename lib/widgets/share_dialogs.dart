// Share dialogs cover duration input plus copy-friendly link confirmation flows.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

const List<_DurationPreset> _durationPresets = <_DurationPreset>[
  _DurationPreset(label: '1小时', hours: 1),
  _DurationPreset(label: '24小时', hours: 24),
  _DurationPreset(label: '3天', hours: 72),
  _DurationPreset(label: '7天', hours: 168),
];

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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in _durationPresets)
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () {
                          controller.text = preset.hours.toString();
                          setDialogState(() => errorText = null);
                        },
                        child: Text(preset.label),
                      ),
                  ],
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
                ShadButton.outline(
                  onPressed: () async {
                    try {
                      await openShareUrl(record.url);
                    } catch (error) {
                      if (!dialogContext.mounted) {
                        return;
                      }
                      showAppErrorToast(
                        dialogContext,
                        message: error.toString(),
                      );
                    }
                  },
                  child: const Text('打开链接'),
                ),
                const SizedBox(width: 10),
                ShadButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: record.url));
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    showAppToast(context, message: '分享链接已复制');
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

Future<void> openShareUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    throw Exception('分享链接无效');
  }
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) {
    throw Exception('无法打开分享链接');
  }
}

class _DurationPreset {
  const _DurationPreset({required this.label, required this.hours});

  final String label;
  final int hours;
}
