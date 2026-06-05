// File preview dialog centralizes inline preview and fallback download actions.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/utils/file_preview_type.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FilePreviewDialog extends StatelessWidget {
  const FilePreviewDialog({
    super.key,
    required this.object,
    required this.kind,
    required this.source,
    required this.loading,
    required this.errorText,
    required this.onSaveAs,
    required this.onDownload,
  });

  final ObjectInfo object;
  final FilePreviewKind kind;
  final FilePreviewSource? source;
  final bool loading;
  final String? errorText;
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
              child: _content(context),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
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

  Widget _content(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (errorText != null) {
      return _message(context, Icons.error_outline, errorText!);
    }
    if (kind == FilePreviewKind.image && source?.bytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: Image.memory(
            source!.bytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _message(
              context,
              Icons.broken_image_outlined,
              '图片预览失败，可以下载后查看。',
            ),
          ),
        ),
      );
    }
    if (kind == FilePreviewKind.image && source?.uri != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: Image.network(
            source!.uri!.toString(),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _message(
              context,
              Icons.broken_image_outlined,
              '图片预览失败，可以下载后查看。',
            ),
          ),
        ),
      );
    }
    return _message(context, _iconForKind(kind), _fallbackText(kind));
  }

  Widget _message(BuildContext context, IconData icon, String text) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForKind(FilePreviewKind kind) {
    return switch (kind) {
      FilePreviewKind.video => Icons.movie_outlined,
      FilePreviewKind.pdf => Icons.picture_as_pdf_outlined,
      FilePreviewKind.word => Icons.description_outlined,
      FilePreviewKind.image => Icons.image_outlined,
      FilePreviewKind.unsupported => Icons.visibility_off_outlined,
    };
  }

  String _fallbackText(FilePreviewKind kind) {
    return switch (kind) {
      FilePreviewKind.video => '当前客户端暂不支持内嵌视频预览，需要下载后查看。',
      FilePreviewKind.pdf => '当前客户端暂不支持内嵌 PDF 预览，需要下载后查看。',
      FilePreviewKind.word => '当前客户端暂不支持内嵌 Word 预览，需要下载后查看。',
      FilePreviewKind.image => '当前图片无法预览，需要下载后查看。',
      FilePreviewKind.unsupported => '暂不支持该文件类型预览，需要下载后查看。',
    };
  }
}
