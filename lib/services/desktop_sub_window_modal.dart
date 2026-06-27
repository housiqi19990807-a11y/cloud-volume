// Helpers for modal-like detached windows: parent scrim + non-movable child chrome.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:window_manager/window_manager.dart';

const String kModalOverlayReleaseMethod = 'modal_overlay_release';

Future<String> currentWindowId() async {
  final c = await WindowController.fromCurrentEngine();
  return c.windowId;
}

void acquireParentModalOverlay() {
  DesktopModalOverlayController.instance.acquire();
}

Future<void> releaseModalOverlayOnCreator(String creatorWindowId) async {
  final controllers = await WindowController.getAll();
  for (final c in controllers) {
    if (c.windowId == creatorWindowId) {
      await c.invokeMethod(kModalOverlayReleaseMethod, null);
      return;
    }
  }
}

Future<void> notifyCreatorModalOverlayRelease(String? creatorWindowId) async {
  final id = creatorWindowId?.trim() ?? '';
  if (id.isEmpty) return;
  await releaseModalOverlayOnCreator(id);
}

Future<Map<String, dynamic>?> _fetchCreatorBounds(String creatorWindowId) async {
  final id = creatorWindowId.trim();
  if (id.isEmpty) return null;
  final controllers = await WindowController.getAll();
  WindowController? target;
  for (final c in controllers) {
    if (c.windowId == id) {
      target = c;
      break;
    }
  }
  if (target == null) return null;
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      final raw = await target.invokeMethod('get_window_bounds');
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {}
    await Future<void>.delayed(Duration(milliseconds: 40 + attempt * 30));
  }
  return null;
}


Future<Map<String, double>> readLocalWindowBounds() async {
  final bounds = await windowManager.getBounds();
  return {
    'left': bounds.left,
    'top': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };
}

/// Prefer [creatorFrame*] captured on the parent engine before spawn (reliable).
Future<void> positionChildCenteredFromFrame({
  required Size size,
  double? anchorFrameLeft,
  double? anchorFrameTop,
  double? anchorFrameWidth,
  double? anchorFrameHeight,
  double? creatorFrameLeft,
  double? creatorFrameTop,
  double? creatorFrameWidth,
  double? creatorFrameHeight,
  String? creatorWindowId,
}) async {
  final left = anchorFrameLeft ?? creatorFrameLeft;
  final top = anchorFrameTop ?? creatorFrameTop;
  final width = anchorFrameWidth ?? creatorFrameWidth;
  final height = anchorFrameHeight ?? creatorFrameHeight;
  if (left != null &&
      top != null &&
      width != null &&
      height != null &&
      width > 0 &&
      height > 0) {
    await windowManager.setBounds(
      Rect.fromLTWH(
        left + (width - size.width) / 2,
        top + (height - size.height) / 2,
        size.width,
        size.height,
      ),
    );
    return;
  }
  await positionChildCenteredOnCreator(creatorWindowId ?? '', size);
}

/// Centers this window over the creator engine's NSWindow bounds (not cursor screen).
Future<void> positionChildCenteredOnCreator(
  String creatorWindowId,
  Size size,
) async {
  final bounds = await _fetchCreatorBounds(creatorWindowId);
  if (bounds != null) {
    final px = (bounds['x'] as num).toDouble();
    final py = (bounds['y'] as num).toDouble();
    final pw = (bounds['width'] as num).toDouble();
    final ph = (bounds['height'] as num).toDouble();
    await windowManager.setBounds(
      Rect.fromLTWH(
        px + (pw - size.width) / 2,
        py + (ph - size.height) / 2,
        size.width,
        size.height,
      ),
    );
    return;
  }
  await windowManager.setSize(size);
  await windowManager.setAlignment(Alignment.center);
}

/// Resizes while keeping the current window center fixed (step 1 -> step 2).
Future<void> resizeKeepingWindowCenter(Size size) async {
  final bounds = await windowManager.getBounds();
  final cx = bounds.left + bounds.width / 2;
  final cy = bounds.top + bounds.height / 2;
  await windowManager.setBounds(
    Rect.fromLTWH(
      cx - size.width / 2,
      cy - size.height / 2,
      size.width,
      size.height,
    ),
  );
}

Future<void> applyModalChildWindowChrome() async {
  await windowManager.setMovable(false);
  if (await windowManager.isFocused()) {
    await windowManager.setAlwaysOnTop(true);
  }
}

Future<void> clearModalChildWindowChrome() async {
  try {
    await windowManager.setAlwaysOnTop(false);
  } catch (_) {}
}


const String kModalBringToFrontMethod = 'modal_bring_to_front';

Future<void> bringTopModalChildToFront() async {
  final childId = DesktopModalOverlayController.instance.topChildWindowId;
  if (childId == null) return;
  final controllers = await WindowController.getAll();
  for (final c in controllers) {
    if (c.windowId == childId) {
      await c.invokeMethod(kModalBringToFrontMethod, null);
      return;
    }
  }
}


const String kModalClearAlwaysOnTopMethod = 'modal_clear_always_on_top';

bool _isModalSubWindowArguments(String arguments) {
  if (arguments.trim().isEmpty) return false;
  return arguments.contains('sync_editor') ||
      arguments.contains('remote_directory_picker');
}

/// Clears always-on-top on every modal sub-window (nested stack included).
Future<void> clearAlwaysOnTopForAllModalChildren() async {
  final controllers = await WindowController.getAll();
  for (final c in controllers) {
    if (!_isModalSubWindowArguments(c.arguments)) continue;
    try {
      await c.invokeMethod(kModalClearAlwaysOnTopMethod, null);
    } catch (_) {}
  }
}


const String kModalShowWindowMethod = 'modal_show_window';

/// Shows ancestor modal windows (main + middle) without stealing focus.
Future<void> showAncestorModalWindows(Iterable<String> windowIds) async {
  final seen = <String>{};
  final controllers = await WindowController.getAll();
  for (final rawId in windowIds) {
    final id = rawId.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    for (final c in controllers) {
      if (c.windowId == id) {
        try {
          await c.invokeMethod(kModalShowWindowMethod, null);
        } catch (_) {}
        break;
      }
    }
  }
}


/// Drops stale scrim state when no modal sub-windows are running (e.g. child killed).
Future<void> reconcileModalOverlayWithOpenChildren() async {
  final controllers = await WindowController.getAll();
  final hasModalChild = controllers.any((c) => _isModalSubWindowArguments(c.arguments));
  if (!hasModalChild) {
    DesktopModalOverlayController.instance.reset();
  }
}
