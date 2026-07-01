// Bridges native macOS Cmd+V/C into Flutter via a method channel.
//
// The Flutter macOS engine routes key equivalents through FlutterView.keyDown:
// (a plain NSView), whose interpretKeyEvents: sends the event into the TSM
// input context where paste:/copy: are silently swallowed before they reach
// the engine keyboard manager or Flutter Shortcuts. To work around this, the
// macOS Runner intercepts Cmd+V/C at the window level and invokes this channel
// so the Dart side can handle the shortcut directly.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Singleton that listens for native clipboard-shortcut callbacks and
/// dispatches them to the currently registered handler.
class ClipboardShortcutChannel {
  ClipboardShortcutChannel._();

  static final ClipboardShortcutChannel instance =
      ClipboardShortcutChannel._();

  static const _channel = MethodChannel('cloud_volume/clipboard_shortcut');

  VoidCallback? _onPaste;
  VoidCallback? _onCopy;
  bool _listening = false;

  /// Register the callbacks and start listening. Call once after bootstrap.
  void start({required VoidCallback onPaste, required VoidCallback onCopy}) {
    _onPaste = onPaste;
    _onCopy = onCopy;
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'paste':
          _onPaste?.call();
          break;
        case 'copy':
          _onCopy?.call();
          break;
      }
    });
  }

  /// Whether the native channel is available (desktop builds only).
  bool get isSupported => !kIsWeb && Platform.isMacOS;
}
