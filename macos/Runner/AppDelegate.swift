import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The desktop app should quit once the main window closes.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // Preserve the default secure state restoration behavior for the Flutter host.
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
