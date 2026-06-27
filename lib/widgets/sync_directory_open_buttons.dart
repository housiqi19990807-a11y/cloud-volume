// 同步配置相关 UI：打开本地目录 / 在文件管理中打开远端同步目录。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/services/local_file_opener.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/services/sync_directory_navigation.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SyncDirectoryOpenButtons extends StatelessWidget {
  const SyncDirectoryOpenButtons({
    super.key,
    required this.localPath,
    required this.remoteOpen,
    this.compact = false,
  });

  final String localPath;
  final SyncRemoteOpenRequest? remoteOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 6.0 : 8.0;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: localPath.trim().isEmpty
              ? null
              : () => openLocal(context, localPath.trim()),
          child: Text(compact ? '本地目录' : '打开本地目录'),
        ),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: remoteOpen == null
              ? null
              : () => _openRemote(context, remoteOpen!),
          child: Text(compact ? '同步目录' : '打开同步目录'),
        ),
      ],
    );
  }

  static Future<void> openLocal(BuildContext context, String path) async {
    try {
      await LocalFileOpener.openPath(path);
    } catch (e) {
      if (!context.mounted) return;
      showAppErrorToast(context, message: '无法打开本地目录：$e');
    }
  }

  static void _openRemote(BuildContext context, SyncRemoteOpenRequest req) {
    SyncDirectoryNavigation.instance.openRemote(req);
  }

  /// 子窗口内调用：转发给主窗口（creatorWindowId 为主引擎 id）。
  static Future<void> openRemoteViaParentWindow(
    BuildContext context, {
    required String? creatorWindowId,
    required SyncRemoteOpenRequest request,
  }) async {
    if (creatorWindowId == null || creatorWindowId.isEmpty) {
      SyncDirectoryNavigation.instance.openRemote(request);
      return;
    }
    try {
      final controller = WindowController.fromWindowId(creatorWindowId);
      await controller.invokeMethod('open_sync_remote_directory', {
        'request': request.toJson(),
      });
    } catch (_) {
      SyncDirectoryNavigation.instance.openRemote(request);
    }
  }
}
