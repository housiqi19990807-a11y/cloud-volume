import Cocoa
import FlutterMacOS

// WindowCoordinator centralizes how the main Flutter window is created and shown.
enum WindowCoordinator {
  static func configure(window: NSWindow, controller: FlutterViewController) {
    let frame = window.frame
    window.contentViewController = controller
    window.setFrame(frame, display: true)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
    window.toolbar = nil
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 1320, height: 860))
    window.minSize = NSSize(width: 980, height: 680)
    RegisterGeneratedPlugins(registry: controller)
  }

  static func createMainWindow() -> MainFlutterWindow {
    let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )
    let controller = FlutterViewController()
    configure(window: window, controller: controller)
    window.center()
    return window
  }

  static func show(window: NSWindow?) -> NSWindow {
    let resolvedWindow = window ?? createMainWindow()
    resolvedWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return resolvedWindow
  }
}

// MainFlutterWindow uses a transparent titlebar so Flutter renders
// seamlessly under the traffic-light area, matching modern macOS apps.
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    WindowCoordinator.configure(window: self, controller: flutterViewController)
    super.awakeFromNib()
  }
}
