// File preview dialog centralizes inline preview and fallback download actions.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/utils/file_preview_type.dart';
import 'package:remote_storage/widgets/file_preview_pane.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FilePreviewDialog extends StatelessWidget {
  const FilePreviewDialog({
    super.key,
    required this.object,
    required this.kind,
    required this.source,
    required this.loading,
    required this.errorText,
    this.onOpenWithSystem,
    required this.onSaveAs,
    required this.onDownload,
  });

  final ObjectInfo object;
  final FilePreviewKind kind;
  final FilePreviewSource? source;
  final bool loading;
  final String? errorText;
  final VoidCallback? onOpenWithSystem;
  final VoidCallback onSaveAs;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: Text(object.displayName),
      description: Text(previewKindLabel(kind)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 420,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.border),
              ),
              child: FilePreviewPane(
                kind: kind,
                source: source,
                loading: loading,
                errorText: errorText,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                if (onOpenWithSystem != null) ...[
                  const SizedBox(width: 10),
                  ShadButton.outline(
                    onPressed: onOpenWithSystem,
                    child: const Text('用系统打开'),
                  ),
                ],
                const SizedBox(width: 10),
                ShadButton.outline(
                  onPressed: loading ? null : onSaveAs,
                  child: const Text('另存为'),
                ),
                const SizedBox(width: 10),
                ShadButton(
                  onPressed: loading ? null : onDownload,
                  child: const Text('下载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
