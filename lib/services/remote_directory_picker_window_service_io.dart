// Opens the remote-directory browser as a detached OS window and awaits the pick result.

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_directory_picker_result_payload.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';

class RemoteDirectoryPickerWindowService {
  RemoteDirectoryPickerWindowService._();

  static final RemoteDirectoryPickerWindowService instance =
      RemoteDirectoryPickerWindowService._();

  bool get isSupported => true;

  Future<RemoteDirectoryResult?> openPicker({
    required List<FileManagerBucketEntry> buckets,
    RemoteDirectoryResult? initial,
  }) async {
    await DesktopWindowMethodHost.ensureInstalled();
    final creator = await WindowController.fromCurrentEngine();
    acquireParentModalOverlay();
    final completer = Completer<RemoteDirectoryResultPayload?>();
    final requestId =
        DesktopWindowMethodHost.registerRemoteDirectoryRequest(completer);
    final args = RemoteDirectoryPickerWindowArgs(
      requestId: requestId,
      creatorWindowId: creator.windowId,
      buckets: buckets,
      initialBucket: initial?.bucket,
      initialPrefix: initial?.prefix,
      initialProfileName: initial?.profileName,
    );
    try {
      await WindowController.create(
        WindowConfiguration(arguments: args.toArguments()),
      );
      final payload = await completer.future;
      return payload?.toResult();
    } finally {
      await releaseModalOverlayOnCreator(creator.windowId);
    }
  }
}
