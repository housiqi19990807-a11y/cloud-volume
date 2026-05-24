import Cocoa
import FlutterMacOS

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
    let alert = NSAlert()
    alert.messageText = "退出云卷"
    alert.informativeText = "确定要退出应用，还是仅将主窗口最小化到托盘？"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "确定退出")
    alert.addButton(withTitle: "最小化到托盘")
    alert.addButton(withTitle: "取消")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      NSApp.terminate(nil)
    case .alertSecondButtonReturn:
      hideYunjuanMainWindow()
    default:
      return
    }
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
    self.setContentSize(NSSize(width: 1160, height: 740))
    self.minSize = NSSize(width: 920, height: 620)

    RegisterGeneratedPlugins(registry: flutterViewController)
    menuBarController = MenuBarController()

    super.awakeFromNib()
  }
}
