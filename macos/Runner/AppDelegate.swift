import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?
  private var statusMenu: NSMenu?
  private weak var mainWindow: NSWindow?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    mainWindow = NSApp.windows.first
    installStatusItem()
  }

  // Keep the app alive after the window closes so the status item can reopen it.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Preserve the default secure state restoration behavior for the Flutter host.
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      openMainWindow(nil)
    }
    return true
  }

  @objc private func openMainWindow(_ sender: Any?) {
    mainWindow = WindowCoordinator.show(window: reusableMainWindow())
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    guard let button = item.button else {
      return
    }

    button.image = makeStatusBarImage()
    button.imagePosition = .imageLeading
    button.title = "云卷"
    button.toolTip = "打开云卷"
    button.imageScaling = .scaleProportionallyDown
    button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    item.menu = buildStatusMenu()
    statusItem = item
  }

  private func buildStatusMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      withTitle: "打开云卷",
      action: #selector(openMainWindow(_:)),
      keyEquivalent: ""
    )
    menu.addItem(
      withTitle: "隐藏主窗口",
      action: #selector(hideMainWindow(_:)),
      keyEquivalent: ""
    )
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "退出云卷",
      action: #selector(terminateApp(_:)),
      keyEquivalent: "q"
    )
    menu.items.forEach { $0.target = self }
    statusMenu = menu
    return menu
  }

  private func makeStatusBarImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()

    let drive = NSBezierPath(roundedRect: NSRect(x: 2.0, y: 2.5, width: 14.0, height: 7.8), xRadius: 2.8, yRadius: 2.8)
    NSColor.black.setFill()
    drive.fill()

    let cloud = NSBezierPath()
    cloud.move(to: NSPoint(x: 4.2, y: 10.2))
    cloud.curve(to: NSPoint(x: 6.8, y: 13.8), controlPoint1: NSPoint(x: 3.6, y: 12.0), controlPoint2: NSPoint(x: 4.8, y: 13.8))
    cloud.curve(to: NSPoint(x: 10.2, y: 14.4), controlPoint1: NSPoint(x: 7.4, y: 14.8), controlPoint2: NSPoint(x: 9.0, y: 14.9))
    cloud.curve(to: NSPoint(x: 12.8, y: 13.1), controlPoint1: NSPoint(x: 11.2, y: 14.0), controlPoint2: NSPoint(x: 12.0, y: 13.6))
    cloud.curve(to: NSPoint(x: 15.0, y: 10.5), controlPoint1: NSPoint(x: 14.2, y: 13.0), controlPoint2: NSPoint(x: 15.0, y: 11.8))
    cloud.line(to: NSPoint(x: 15.0, y: 9.6))
    cloud.line(to: NSPoint(x: 4.2, y: 9.6))
    cloud.close()
    cloud.fill()

    let slot = NSBezierPath(roundedRect: NSRect(x: 5.2, y: 5.1, width: 7.6, height: 1.6), xRadius: 0.8, yRadius: 0.8)
    NSColor.white.setFill()
    slot.fill()

    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  @objc private func terminateApp(_ sender: Any?) {
    NSApp.terminate(sender)
  }

  @objc private func hideMainWindow(_ sender: Any?) {
    reusableMainWindow()?.orderOut(sender)
  }

  private func reusableMainWindow() -> NSWindow? {
    if let mainWindow, mainWindow.isVisible || !mainWindow.isReleasedWhenClosed {
      return mainWindow
    }
    return NSApp.windows.first
  }
}
