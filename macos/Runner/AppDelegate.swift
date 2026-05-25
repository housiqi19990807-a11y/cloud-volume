import Cocoa
import Darwin
import FlutterMacOS

// App delegate keeps 云卷 alive after the main window hides so the menu-bar
// workflow can reopen it like the reference macOS app.
@main
class AppDelegate: FlutterAppDelegate {
  typealias BridgeInvoke = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
  typealias BridgeFreeString = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showYunjuanMainWindow()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    _ = cleanupMountedBuckets()
    super.applicationWillTerminate(notification)
  }

  // Termination cleanup runs in the host process so mounted desktop entries do
  // not survive app exit and leave Finder accesses hanging.
  private func cleanupMountedBuckets() -> Bool {
    guard
      let bridgePath = bundledBridgePath()
    else {
      return false
    }

    return bridgePath.withCString { cBridgePath in
      guard
        let handle = dlopen(cBridgePath, RTLD_NOW),
      let invokeSymbol = dlsym(handle, "RemoteStorageInvoke"),
      let freeSymbol = dlsym(handle, "RemoteStorageFreeString")
      else {
        return false
      }
      defer { dlclose(handle) }

      let invoke = unsafeBitCast(invokeSymbol, to: BridgeInvoke.self)
      let freeString = unsafeBitCast(freeSymbol, to: BridgeFreeString.self)

      return "cleanup_mounts".withCString { methodCString in
        "{}".withCString { argsCString in
          let response = invoke(methodCString, argsCString)
          defer { freeString(response) }
          return response != nil
        }
      }
    }
  }

  private func bundledBridgePath() -> String? {
    let fileManager = FileManager.default
    let candidates = [
      Bundle.main.privateFrameworksPath.map { "\($0)/libremote_storage_bridge.dylib" },
      Bundle.main.builtInPlugInsPath.map { "\($0)/libremote_storage_bridge.dylib" },
      Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(
        "libremote_storage_bridge.dylib"
      ).path,
    ].compactMap { $0 }

    for candidate in candidates where fileManager.fileExists(atPath: candidate) {
      return candidate
    }
    return nil
  }
}
