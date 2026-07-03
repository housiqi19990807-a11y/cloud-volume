// Desktop sync-editor sub-window service opens an ad-hoc editor as a
// standalone OS window with its own Flutter engine and bridge connection.
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';

class SyncEditorWindowService {
  SyncEditorWindowService._();

  static final SyncEditorWindowService instance = SyncEditorWindowService._();

  bool get isSupported => true;

  Future<bool> openEditor({
    required List<String> profileNames,
    Map<String, dynamic>? initialProfile,
  }) async {
    acquireParentModalOverlay();
    // Yield to the event loop so the parent scrim can render its loading
    // spinner before the expensive sub-window spawn blocks the UI thread.
    await Future<void>.delayed(Duration.zero);
    try {
      final creator = await WindowController.fromCurrentEngine();
      final creatorFrame = await readLocalWindowBounds();
      final args = SyncEditorWindowArgs(
        creatorWindowId: creator.windowId,
        profileNames: profileNames,
        initialProfileJson: initialProfile,
        creatorFrameLeft: creatorFrame['left'],
        creatorFrameTop: creatorFrame['top'],
        creatorFrameWidth: creatorFrame['width'],
        creatorFrameHeight: creatorFrame['height'],
      );
      final child = await WindowController.create(
        WindowConfiguration(arguments: args.toArguments()),
      );
      DesktopModalOverlayController.instance.registerChildWindow(child.windowId);
      return true;
    } catch (_) {
      await notifyCreatorModalOverlayRelease(
        (await WindowController.fromCurrentEngine()).windowId,
      );
      rethrow;
    }
  }
}
