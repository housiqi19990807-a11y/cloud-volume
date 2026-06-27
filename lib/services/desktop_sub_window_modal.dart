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

/// Centers this window over the creator engine's NSWindow bounds (not cursor screen).
Future<void> positionChildCenteredOnCreator(
  String creatorWindowId,
  Size size,
) async {
  final id = creatorWindowId.trim();
  if (id.isEmpty) {
    await windowManager.setBounds(
      null,
      size: size,
      position: null,
    );
    await windowManager.setAlignment(Alignment.center);
    return;
  }
  final controllers = await WindowController.getAll();
  for (final c in controllers) {
    if (c.windowId != id) continue;
    final raw = await c.invokeMethod('get_window_bounds');
    if (raw is! Map) break;
    final px = (raw['x'] as num).toDouble();
    final py = (raw['y'] as num).toDouble();
    final pw = (raw['width'] as num).toDouble();
    final ph = (raw['height'] as num).toDouble();
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

Future<void> applyModalChildWindowChrome() async {
  await windowManager.setMovable(false);
  await windowManager.setAlwaysOnTop(true);
}

Future<void> clearModalChildWindowChrome() async {
  try {
    await windowManager.setAlwaysOnTop(false);
  } catch (_) {}
}
