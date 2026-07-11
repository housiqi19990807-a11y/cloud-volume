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
      bootstrap: () => defaultRemoteStorageApiFactory(),
      onClose: () => _sendResult(args, _pendingResult),
      contentBuilder: (context, api) => _PickerContent(args: args, api: api),
    );
  }
}

/// Module-level holder for the picker's confirmed result.
/// Set by [_PickerContent]'s onConfirm; read by the onClose callback above.
RemoteDirectoryResult? _pendingResult;

/// Holds the picker dialog. onConfirm stashes the result so the generic
/// shell's onClose can send it to the creator window before closing.
class _PickerContent extends StatelessWidget {
  const _PickerContent({required this.args, required this.api});

  final RemoteDirectoryPickerWindowArgs args;
  final RemoteStorageGateway api;

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
      onCancel: () {},
      onConfirm: (result) => _pendingResult = result,
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
