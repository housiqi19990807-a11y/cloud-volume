// Windows window-control channel keeps custom desktop chrome in Flutter while
// the native runner still owns the actual window state transitions.

import 'dart:io';

import 'package:flutter/services.dart';

class WindowControls {
  WindowControls._();

  static const MethodChannel _channel = MethodChannel(
    'remote_storage/window_controls',
  );

  static bool get supported => Platform.isWindows;

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

  static Future<void> startDrag() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('startDrag');
  }
}
