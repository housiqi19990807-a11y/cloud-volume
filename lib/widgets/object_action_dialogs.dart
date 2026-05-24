// Object action dialogs keep rename/delete prompts out of the main page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum FileObjectAction { download, rename, delete }

Future<FileObjectAction?> showObjectActionMenu(
  BuildContext context,
  Offset position,
  ObjectInfo object,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<FileObjectAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    ),
    items: <PopupMenuEntry<FileObjectAction>>[
      if (!object.isDir)
        const PopupMenuItem<FileObjectAction>(
          value: FileObjectAction.download,
          child: Text('下载'),
        ),
      const PopupMenuItem<FileObjectAction>(
        value: FileObjectAction.rename,
        child: Text('重命名'),
      ),
      const PopupMenuItem<FileObjectAction>(
        value: FileObjectAction.delete,
        child: Text('删除'),
      ),
    ],
  );
}

Future<String?> showRenameObjectDialog(
  BuildContext context,
  ObjectInfo object,
) async {
  final controller = TextEditingController(text: object.displayName);
  try {
    return await showShadDialog<String?>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('重命名'),
        description: Text(object.isDir ? '输入新的目录名称。' : '输入新的文件名称。'),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              ShadInput(controller: controller),
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
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(controller.text.trim()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool> showDeleteObjectDialog(
  BuildContext context,
  ObjectInfo object,
) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('删除'),
          description: Text(
            object.isDir ? '将删除整个目录及其内容。此操作不可撤销。' : '将删除这个文件。此操作不可撤销。',
          ),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  object.displayName,
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
                      child: const Text('删除'),
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
