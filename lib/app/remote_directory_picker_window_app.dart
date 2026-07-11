// Remote directory picker sub-window built on the shared DesktopModalSubWindowApp.
// The picker returns a result to the creator window via the [onClose] callback,
// which fires before the generic shell runs its close sequence.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_directory_picker_result_payload.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/app/desktop_modal_sub_window_app.dart';

class RemoteDirectoryPickerWindowApp extends StatelessWidget {
  const RemoteDirectoryPickerWindowApp({super.key, required this.args});

  final RemoteDirectoryPickerWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return DesktopModalSubWindowApp<RemoteStorageGateway>(
      title: '选择远端目录',
      creatorWindowId: args.creatorWindowId,
      useParentFocusRelay: false,
      // Picker uses Expanded + ListView; outer scroll would break flex layout.
      scrollable: false,
      bootstrap: () => defaultRemoteStorageApiFactory(),
      // Title-bar close / cancel with no selection → null result.
      onClose: () => _sendResult(args, _pendingResult),
      contentBuilder: (context, api, close) => _PickerContent(
        args: args,
        api: api,
        close: close,
      ),
    );
  }
}

/// Module-level holder for the picker's confirmed result.
/// Set by [_PickerContent]'s onConfirm; read by the onClose callback above.
RemoteDirectoryResult? _pendingResult;

/// Holds the picker dialog. onConfirm/onCancel stash the result (or clear it)
/// then call [close], which runs the shell's onClose → close sequence.
class _PickerContent extends StatelessWidget {
  const _PickerContent({
    required this.args,
    required this.api,
    required this.close,
  });

  final RemoteDirectoryPickerWindowArgs args;
  final RemoteStorageGateway api;
  final Future<void> Function() close;

  RemoteDirectoryResult? get _initial {
    if (args.initialBucket == null) return null;
    final entry = args.buckets.where((b) {
      return b.bucket.name == args.initialBucket &&
          b.profileName == (args.initialProfileName ?? b.profileName);
    }).firstOrNull;
    if (entry == null) return null;
    return RemoteDirectoryResult(
      bucket: args.initialBucket!,
      prefix: args.initialPrefix ?? '',
      profileName: entry.profileName,
      config: entry.config,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RemoteDirectoryPickerDialog(
      api: api,
      buckets: args.buckets,
      initial: _initial,
      asDialog: false,
      onCancel: () {
        _pendingResult = null;
        close();
      },
      onConfirm: (result) {
        _pendingResult = result;
        close();
      },
    );
  }
}

/// Sends the result payload to the creator window via method channel.
Future<void> _sendResult(
  RemoteDirectoryPickerWindowArgs args,
  RemoteDirectoryResult? result,
) async {
  final payload = <String, dynamic>{
    'requestId': args.requestId,
    'result': result == null
        ? null
        : RemoteDirectoryResultPayload.fromResult(result).toJson(),
  };
  final targetId = args.creatorWindowId;
  final controllers = await WindowController.getAll();
  for (final c in controllers) {
    if (c.windowId == targetId) {
      await c.invokeMethod('remote_directory_picker_result', payload);
      return;
    }
  }
}
