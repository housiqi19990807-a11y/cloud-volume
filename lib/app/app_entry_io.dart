// Desktop entry chooses between the main app and detached preview sub-windows.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/app/account_editor_window_app.dart';
import 'package:remote_storage/app/file_preview_window_app.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/app/remote_directory_picker_window_app.dart';
import 'package:remote_storage/app/sync_editor_window_app.dart';
import 'package:remote_storage/models/account_editor_window_args.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/models/file_preview_window_args.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runRemoteStorageEntry(List<String> args) async {
  final controller = await WindowController.fromCurrentEngine();
  final arguments = controller.arguments;
  await windowManager.ensureInitialized();

  if (FilePreviewWindowArgs.matches(arguments)) {
    final previewArgs = FilePreviewWindowArgs.fromArguments(arguments);
    await _configurePreviewWindow(previewArgs.title);
    runApp(FilePreviewWindowApp(args: previewArgs));
    return;
  }

  if (AccountEditorWindowArgs.matches(arguments)) {
    final editorArgs = AccountEditorWindowArgs.fromArguments(arguments);
    await DesktopWindowMethodHost.ensureInstalled();
    await _configureAccountEditorWindow(editorArgs);
    runApp(AccountEditorWindowApp(args: editorArgs));
    return;
  }

  if (SyncEditorWindowArgs.matches(arguments)) {
    final editorArgs = SyncEditorWindowArgs.fromArguments(arguments);
    await DesktopWindowMethodHost.ensureInstalled();
    await _configureSyncEditorWindow(editorArgs);
    runApp(SyncEditorWindowApp(args: editorArgs));
    return;
  }

  if (RemoteDirectoryPickerWindowArgs.matches(arguments)) {
    final pickerArgs = RemoteDirectoryPickerWindowArgs.fromArguments(arguments);
    await DesktopWindowMethodHost.ensureInstalled();
    await _configureRemoteDirectoryPickerWindow(pickerArgs);
    runApp(RemoteDirectoryPickerWindowApp(args: pickerArgs));
    return;
  }

  runApp(const RemoteStorageApp());
}

Future<void> _configureSyncEditorWindow(SyncEditorWindowArgs args) async {
  final title = args.initialProfile != null ? '编辑同步配置' : '新建同步配置';
  const options = WindowOptions(
    size: Size(560, 480),
    minimumSize: Size(520, 400),
    center: false,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await applyModalChildWindowChrome();
    await windowManager.setTitle(title);
    await windowManager.show();
    await positionChildCenteredFromFrame(
      size: const Size(560, 480),
      creatorFrameLeft: args.creatorFrameLeft,
      creatorFrameTop: args.creatorFrameTop,
      creatorFrameWidth: args.creatorFrameWidth,
      creatorFrameHeight: args.creatorFrameHeight,
      creatorWindowId: args.creatorWindowId,
    );
    await windowManager.focus();
  });
}

Future<void> _configurePreviewWindow(String title) async {
  const options = WindowOptions(
    size: Size(1040, 760),
    minimumSize: Size(720, 520),
    center: true,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitle(title);
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> _configureRemoteDirectoryPickerWindow(RemoteDirectoryPickerWindowArgs args) async {
  const options = WindowOptions(
    size: Size(720, 560),
    minimumSize: Size(560, 440),
    center: false,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
    await windowManager.waitUntilReadyToShow(options, () async {
      await applyModalChildWindowChrome();
      await windowManager.setTitle('选择远端目录');
      await windowManager.show();
      await positionChildCenteredFromFrame(
        size: const Size(720, 560),
        anchorFrameLeft: args.anchorFrameLeft,
        anchorFrameTop: args.anchorFrameTop,
        anchorFrameWidth: args.anchorFrameWidth,
        anchorFrameHeight: args.anchorFrameHeight,
        creatorFrameLeft: args.creatorFrameLeft,
        creatorFrameTop: args.creatorFrameTop,
        creatorFrameWidth: args.creatorFrameWidth,
        creatorFrameHeight: args.creatorFrameHeight,
        creatorWindowId: args.creatorWindowId,
      );
      await windowManager.focus();
    });
  }

  Future<void> _configureAccountEditorWindow(AccountEditorWindowArgs args) async {
    final title = args.editing ? '编辑账号' : '新增账号';
    final size = _accountEditorWindowSize(args);
    final options = WindowOptions(
      size: size,
      minimumSize: const Size(480, 400),
      center: false,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await applyModalChildWindowChrome();
      await windowManager.setTitle(title);
      await windowManager.show();
      await positionChildCenteredFromFrame(
        size: size,
        creatorFrameLeft: args.creatorFrameLeft,
        creatorFrameTop: args.creatorFrameTop,
        creatorFrameWidth: args.creatorFrameWidth,
        creatorFrameHeight: args.creatorFrameHeight,
        creatorWindowId: args.creatorWindowId,
      );
      await windowManager.focus();
    });
  }

  Size _accountEditorWindowSize(AccountEditorWindowArgs args) {
    // New account: step 0 is compact (protocol picker); step 1 content is
    // taller but scrolls if needed. Give a comfortable initial size.
    if (!args.editing) return const Size(520, 420);
    // Editing: size by protocol to fit typical content.
    final storageType = args.initialConfig?.storageType;
    return switch (storageType) {
      StorageType.baiduPan => const Size(520, 520),
      StorageType.webdav => const Size(520, 600),
      _ => const Size(520, 700),
    };
  }
