// Unified window configuration for modal sub-windows. Replaces the
// per-window _configure*Window functions that were duplicated in app_entry_io.

import 'dart:ui';

import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:window_manager/window_manager.dart';

/// Configures and shows a modal sub-window with hidden title bar, modal
/// chrome, and centering relative to the creator window frame.
///
/// [size] is the initial window size. [minimumSize] defaults to 480×400.
/// [anchorFrame*] takes priority over [creatorFrame*] for positioning;
/// both fall back to [positionChildCenteredOnCreator] when absent.
Future<void> configureDesktopModalSubWindow({
  required String title,
  required Size size,
  Size minimumSize = const Size(480, 400),
  double? anchorFrameLeft,
  double? anchorFrameTop,
  double? anchorFrameWidth,
  double? anchorFrameHeight,
  double? creatorFrameLeft,
  double? creatorFrameTop,
  double? creatorFrameWidth,
  double? creatorFrameHeight,
  required String creatorWindowId,
}) async {
  final options = WindowOptions(
    size: size,
    minimumSize: minimumSize,
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
      anchorFrameLeft: anchorFrameLeft,
      anchorFrameTop: anchorFrameTop,
      anchorFrameWidth: anchorFrameWidth,
      anchorFrameHeight: anchorFrameHeight,
      creatorFrameLeft: creatorFrameLeft,
      creatorFrameTop: creatorFrameTop,
      creatorFrameWidth: creatorFrameWidth,
      creatorFrameHeight: creatorFrameHeight,
      creatorWindowId: creatorWindowId,
    );
    await windowManager.focus();
  });
}
