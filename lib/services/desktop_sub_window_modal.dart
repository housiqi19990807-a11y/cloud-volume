// Helpers for modal-like detached windows: parent scrim + non-movable child chrome.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';

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
