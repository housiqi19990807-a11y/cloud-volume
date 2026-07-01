// Forwards Cmd+C / Cmd+V from native AppKit menu dispatch into Flutter.
//
// The Flutter engine routes key equivalents through FlutterView.keyDown:,
// which is a plain NSView whose interpretKeyEvents: hands the event to the
// TSM input context and silently swallows paste:/copy: before they ever
// reach the engine keyboard manager or Flutter Shortcuts. This plugin breaks
// that path by routing the Edit-menu Paste/Copy actions over a method channel
// so the Dart side can react directly.

import Cocoa
import FlutterMacOS

enum ClipboardShortcut {
  static let channelName = "cloud_volume/clipboard_shortcut"
}

/// FlutterPlugin that relays paste/copy signals from native menu items to Dart.
final class ClipboardShortcutPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ClipboardShortcutPlugin()
    let channel = FlutterMethodChannel(
      name: ClipboardShortcut.channelName,
      binaryMessenger: registrar.messenger
    )
    instance.channel = channel
    registrar.publish(instance)
    ClipboardShortcutCoordinator.shared.attach(plugin: instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }

  /// Called by native menu/window code when Cmd+V or Cmd+C fires.
  func sendShortcut(_ name: String) {
    channel?.invokeMethod(name, arguments: nil)
  }
}

/// Shared holder so the NSMenuItem targets can reach the plugin instance.
final class ClipboardShortcutCoordinator {
  static let shared = ClipboardShortcutCoordinator()
  private(set) var plugin: ClipboardShortcutPlugin?

  func attach(plugin: ClipboardShortcutPlugin) {
    self.plugin = plugin
  }

  func handlePaste() {
    plugin?.sendShortcut("paste")
  }

  func handleCopy() {
    plugin?.sendShortcut("copy")
  }
}
