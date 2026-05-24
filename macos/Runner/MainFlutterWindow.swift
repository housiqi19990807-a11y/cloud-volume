import Cocoa
import FlutterMacOS

private let yunjuanDefaultWindowSize = NSSize(width: 1160, height: 740)
private let yunjuanMinimumWindowSize = NSSize(width: 920, height: 620)

func yunjuanMainWindow() -> NSWindow? {
  NSApp.windows.first { $0 is MainFlutterWindow } ?? NSApp.mainWindow ?? NSApp.windows.first
}

func showYunjuanMainWindow() {
  guard let window = yunjuanMainWindow() else {
    return
  }
  if window.isMiniaturized {
    window.deminiaturize(nil)
  }
  NSApp.activate(ignoringOtherApps: true)
  window.makeKeyAndOrderFront(nil)
}

func hideYunjuanMainWindow() {
  yunjuanMainWindow()?.orderOut(nil)
}

// MenuBarController owns the macOS tray item so it survives as long as the
// main window object lives, mirroring the proven CloudPlayer setup.
final class MenuBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()

  override init() {
    super.init()
    configureStatusItem()
    configureMenu()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else {
      return
    }
    button.toolTip = "云卷"
    button.lineBreakMode = .byTruncatingTail
    button.imageScaling = .scaleProportionallyDown
    button.imagePosition = .imageLeading
    button.title = " 云卷"
    button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    button.target = self
    button.action = #selector(handleStatusItemPressed(_:))

    if let image = NSImage(named: "TrayIcon")?.copy() as? NSImage {
      image.isTemplate = true
      image.size = NSSize(width: 18, height: 18)
      button.image = image
    } else if let image = NSApp.applicationIconImage.copy() as? NSImage {
      image.isTemplate = true
      image.size = NSSize(width: 18, height: 18)
      button.image = image
    }
  }

  private func configureMenu() {
    let showItem = NSMenuItem(title: "显示主窗口", action: #selector(handleShowMainWindow), keyEquivalent: "")
    showItem.target = self
    let hideItem = NSMenuItem(title: "隐藏到托盘", action: #selector(handleHideMainWindow), keyEquivalent: "")
    hideItem.target = self
    let quitItem = NSMenuItem(title: "退出云卷", action: #selector(handleTerminate), keyEquivalent: "q")
    quitItem.target = self

    menu.autoenablesItems = false
    menu.items = [
      showItem,
      hideItem,
      .separator(),
      quitItem,
    ]
  }

  @objc private func handleStatusItemPressed(_ sender: NSStatusBarButton) {
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: sender.bounds.maxY + 6),
      in: sender
    )
  }

  @objc private func handleShowMainWindow() {
    showYunjuanMainWindow()
  }

  @objc private func handleHideMainWindow() {
    hideYunjuanMainWindow()
  }

  @objc private func handleTerminate() {
    NSApp.terminate(nil)
  }
}

// MainFlutterWindow keeps the macOS host chrome thin and owns the menu-bar
// controller so tray behavior stays alive across window show/hide cycles.
class MainFlutterWindow: NSWindow {
  private var menuBarController: MenuBarController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.toolbar = nil
    self.isReleasedWhenClosed = false
    self.minSize = yunjuanMinimumWindowSize

    RegisterGeneratedPlugins(registry: flutterViewController)
    menuBarController = MenuBarController()

    super.awakeFromNib()

    // Always reopen at the product default size instead of reusing the last
    // window dimensions from a previous app launch.
    DispatchQueue.main.async { [weak self] in
      self?.applyDefaultWindowLayout()
    }
  }

  private func applyDefaultWindowLayout() {
    let targetFrame = centeredWindowFrame(for: yunjuanDefaultWindowSize)
    self.setFrame(targetFrame, display: true)
  }

  private func centeredWindowFrame(for size: NSSize) -> NSRect {
    let referenceScreen = self.screen ?? NSScreen.main
    let visibleFrame = referenceScreen?.visibleFrame ?? self.frame
    let originX = visibleFrame.origin.x + ((visibleFrame.width - size.width) / 2)
    let originY = visibleFrame.origin.y + ((visibleFrame.height - size.height) / 2)
    return NSRect(origin: NSPoint(x: originX, y: originY), size: size)
  }
}
