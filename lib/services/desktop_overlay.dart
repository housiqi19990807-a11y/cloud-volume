// Overlay presentation helper: in-app modals by default; OS sub-windows only
// when debug modal sub-window mode is explicitly enabled.

import 'package:flutter/material.dart';
import 'package:remote_storage/services/account_editor_window_service.dart';
import 'package:remote_storage/services/modal_sub_window_debug.dart';
import 'package:remote_storage/services/remote_directory_picker_window_service.dart';
import 'package:remote_storage/services/sync_editor_window_service.dart';

/// Tries [openSubWindow] only when debug sub-window mode is on and a desktop
/// window service reports support; otherwise uses [showDialog] (in-app modal).
Future<T?> showDesktopOverlayOrDialog<T>({
  required BuildContext context,
  required Future<T?> Function() openSubWindow,
  required Future<T?> Function() showDialog,
}) async {
  final desktopSupported =
      RemoteDirectoryPickerWindowService.instance.isSupported ||
          SyncEditorWindowService.instance.isSupported ||
          AccountEditorWindowService.instance.isSupported;
  if (preferModalSubWindows && desktopSupported) {
    return openSubWindow();
  }
  return showDialog();
}

