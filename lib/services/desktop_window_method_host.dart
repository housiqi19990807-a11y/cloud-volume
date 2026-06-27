// Multiplexes desktop_multi_window method calls on the main engine so multiple
// sub-windows (sync editor, remote directory picker, …) can return results.

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:remote_storage/models/remote_directory_picker_result_payload.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';

class DesktopWindowMethodHost {
  DesktopWindowMethodHost._();

  static bool _installed = false;
  static final Map<String, Completer<RemoteDirectoryResultPayload?>>
      _remoteDirectoryRequests = {};

  /// Registers a single handler on the current (main) window controller.
  static Future<void> ensureInstalled() async {
    if (_installed) return;
    _installed = true;
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler(_onMethodCall);
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'remote_directory_picker_result':
        _completeRemoteDirectory(call.arguments);
        return null;
      case kModalOverlayReleaseMethod:
        DesktopModalOverlayController.instance.release();
        return null;
      case 'get_window_bounds':
        final bounds = await windowManager.getBounds();
        return <String, dynamic>{
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        };
      case 'is_window_focused':
        return await windowManager.isFocused();
      case kModalBringToFrontMethod:
        await windowManager.show();
        await windowManager.focus();
        await applyModalChildWindowChrome();
        return null;
      case kModalClearAlwaysOnTopMethod:
        await clearModalChildWindowChrome();
        return null;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  static String registerRemoteDirectoryRequest(
    Completer<RemoteDirectoryResultPayload?> completer,
  ) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _remoteDirectoryRequests[id] = completer;
    return id;
  }

  static void cancelRemoteDirectoryRequest(String requestId) {
    _remoteDirectoryRequests.remove(requestId)?.complete(null);
  }

  static void _completeRemoteDirectory(dynamic raw) {
    if (raw is! Map) return;
    final requestId = raw['requestId']?.toString();
    if (requestId == null) return;
    final completer = _remoteDirectoryRequests.remove(requestId);
    if (completer == null) return;
    final resultJson = raw['result'];
    if (resultJson == null) {
      completer.complete(null);
      return;
    }
    completer.complete(
      RemoteDirectoryResultPayload.fromJson(
        Map<String, dynamic>.from(resultJson as Map),
      ),
    );
  }
}
