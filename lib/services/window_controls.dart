// Desktop window-control channel keeps custom chrome in Flutter while the
// native runner still owns the actual window state transitions.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:remote_storage/platform/platform_info.dart';

typedef CloseRequestHandler = Future<void> Function();

class WindowControls {
  WindowControls._();

  static const MethodChannel _channel = MethodChannel(
    'remote_storage/window_controls',
  );

  static CloseRequestHandler? _onRequestClose;

  /// Registers the handler invoked when the native host asks Flutter to
  /// decide what an OS-level close gesture (Alt+F4, taskbar close) should do.
  /// Only the Windows runner currently emits `requestClose`.
  static void registerCloseRequestHandler(CloseRequestHandler? handler) {
    _onRequestClose = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'requestClose') {
        final handler = _onRequestClose;
        if (handler != null) {
          await handler();
        }
        return null;
      }
      throw MissingPluginException('unknown method ${call.method}');
    });
  }

  static bool get supported => isWindowsPlatform || isLinuxPlatform;

  static bool get supportsTray => isWindowsPlatform;

  static Future<void> minimize() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('minimize');
  }

  static Future<bool> toggleMaximize() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('toggleMaximize') ?? false;
  }

  static Future<bool> isMaximized() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('isMaximized') ?? false;
  }

  static Future<void> close() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('close');
  }

  /// Asks the native host whether the in-app close button should drive the
  /// "hide to tray vs exit" confirmation. On Windows the host intercepts
  /// WM_CLOSE so Alt+F4 / taskbar close also route through this path.
  static Future<bool> shouldConfirmClose() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('shouldConfirmClose') ?? false;
  }

  static Future<void> hideToTray() async {
    if (!supportsTray) return;
    await _channel.invokeMethod<void>('hideToTray');
  }

  static Future<void> startDrag() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('startDrag');
  }
}
