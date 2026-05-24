import Cocoa
import FlutterMacOS

// MainFlutterWindow uses a transparent titlebar so Flutter renders
// seamlessly under the traffic-light area, matching modern macOS apps.
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Transparent titlebar: traffic lights float over Flutter content.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // Keep traffic lights visible but let content extend underneath.
    self.toolbar = nil

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
