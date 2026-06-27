// Desktop-first overlay helper: prefer detached sub-windows, fall back to ShadDialog on Web.

import 'package:flutter/material.dart';
import 'package:remote_storage/services/remote_directory_picker_window_service.dart';
import 'package:remote_storage/services/sync_editor_window_service.dart';

/// Tries [openSubWindow] on desktop; on Web (or unsupported) uses [showDialog].
Future<T?> showDesktopOverlayOrDialog<T>({
  required BuildContext context,
  required Future<T?> Function() openSubWindow,
  required Future<T?> Function() showDialog,
}) async {
  final useSubWindow = RemoteDirectoryPickerWindowService.instance.isSupported ||
      SyncEditorWindowService.instance.isSupported;
  if (useSubWindow) {
    return openSubWindow();
  }
  return showDialog();
}
