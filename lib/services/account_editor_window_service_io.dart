// Desktop account-editor sub-window service opens the add/edit form as a
// standalone OS window with its own Flutter engine and bridge connection.
// Only available when preferModalSubWindows is true (debug + dart-define).

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/models/account_editor_window_args.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/modal_sub_window_debug.dart';

class AccountEditorWindowService {
  AccountEditorWindowService._();

  static final AccountEditorWindowService instance =
      AccountEditorWindowService._();

  /// True only in debug with USE_MODAL_SUB_WINDOWS=true.
  bool get isSupported => preferModalSubWindows;

  Future<bool> openEditor({
    Map<String, dynamic>? initialConfigJson,
    String? profileName,
    bool editing = false,
    required void Function() onSaved,
  }) async {
    if (!isSupported) return false;
    acquireParentModalOverlay();
    // Yield to the event loop so the parent scrim can render its loading
    // spinner before the expensive sub-window spawn blocks the UI thread.
    await Future<void>.delayed(Duration.zero);
    try {
      final creator = await WindowController.fromCurrentEngine();
      final creatorFrame = await readLocalWindowBounds();
      DesktopWindowMethodHost.registerAccountEditorSavedCallback(
        creator.windowId,
        onSaved,
      );
      final args = AccountEditorWindowArgs(
        creatorWindowId: creator.windowId,
        initialConfigJson: initialConfigJson,
        profileName: profileName,
        editing: editing,
        creatorFrameLeft: creatorFrame['left'],
        creatorFrameTop: creatorFrame['top'],
        creatorFrameWidth: creatorFrame['width'],
        creatorFrameHeight: creatorFrame['height'],
      );
      final child = await WindowController.create(
        WindowConfiguration(arguments: args.toArguments()),
      );
      DesktopModalOverlayController.instance
          .registerChildWindow(child.windowId);
      return true;
    } catch (_) {
      await notifyCreatorModalOverlayRelease(
        (await WindowController.fromCurrentEngine()).windowId,
      );
      rethrow;
    }
  }
}

