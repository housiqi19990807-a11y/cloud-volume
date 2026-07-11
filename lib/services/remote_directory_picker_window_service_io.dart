// Opens the remote-directory browser as a detached OS window and awaits the
// pick result. Only available when preferModalSubWindows is true.

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_directory_picker_result_payload.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/modal_sub_window_debug.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';

class RemoteDirectoryPickerWindowService {
  RemoteDirectoryPickerWindowService._();

  static final RemoteDirectoryPickerWindowService instance =
      RemoteDirectoryPickerWindowService._();

  /// True only in debug with USE_MODAL_SUB_WINDOWS=true.
  bool get isSupported => preferModalSubWindows;

  Future<RemoteDirectoryResult?> openPicker({
    required List<FileManagerBucketEntry> buckets,
    RemoteDirectoryResult? initial,
    double? anchorFrameLeft,
    double? anchorFrameTop,
    double? anchorFrameWidth,
    double? anchorFrameHeight,
    String? rootWindowId,
  }) async {
    if (!isSupported) return null;
    await DesktopWindowMethodHost.ensureInstalled();
    final creator = await WindowController.fromCurrentEngine();
    final localFrame = await readLocalWindowBounds();
    final useAnchor = anchorFrameLeft != null &&
        anchorFrameTop != null &&
        anchorFrameWidth != null &&
        anchorFrameHeight != null;
    final creatorFrame = useAnchor
        ? {
            'left': anchorFrameLeft,
            'top': anchorFrameTop,
            'width': anchorFrameWidth,
            'height': anchorFrameHeight,
          }
        : localFrame;
    acquireParentModalOverlay();
    // Yield to the event loop so the parent scrim can render its loading
    // spinner before the expensive sub-window spawn blocks the UI thread.
    await Future<void>.delayed(Duration.zero);
    final completer = Completer<RemoteDirectoryResultPayload?>();
    final requestId =
        DesktopWindowMethodHost.registerRemoteDirectoryRequest(completer);
    final args = RemoteDirectoryPickerWindowArgs(
      requestId: requestId,
      creatorWindowId: creator.windowId,
      rootWindowId: rootWindowId,
      buckets: buckets,
      initialBucket: initial?.bucket,
      initialPrefix: initial?.prefix,
      initialProfileName: initial?.profileName,
      creatorFrameLeft: creatorFrame['left'],
      creatorFrameTop: creatorFrame['top'],
      creatorFrameWidth: creatorFrame['width'],
      creatorFrameHeight: creatorFrame['height'],
      anchorFrameLeft: useAnchor ? anchorFrameLeft : localFrame['left'],
      anchorFrameTop: useAnchor ? anchorFrameTop : localFrame['top'],
      anchorFrameWidth: useAnchor ? anchorFrameWidth : localFrame['width'],
      anchorFrameHeight: useAnchor ? anchorFrameHeight : localFrame['height'],
    );
    try {
      final child = await WindowController.create(
        WindowConfiguration(arguments: args.toArguments()),
      );
      DesktopModalOverlayController.instance
          .registerChildWindow(child.windowId);
      if (rootWindowId != null && rootWindowId.trim().isNotEmpty) {
        await registerModalChildOnRootEngine(rootWindowId, child.windowId);
      }
      final payload = await completer.future;
      return payload?.toResult();
    } finally {
      await releaseModalOverlayOnCreator(creator.windowId);
    }
  }
}

