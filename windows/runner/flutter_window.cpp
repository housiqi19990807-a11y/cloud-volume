#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayCommandShow = 1001;
constexpr UINT kTrayCommandExit = 1002;
constexpr UINT kTrayMenuAnchorBottom = 0xFFFF;
constexpr wchar_t kTrayTooltip[] = L"Yunjuan";
constexpr wchar_t kTrayShowLabel[] = L"\u663E\u793A\u4E3B\u7A97\u53E3";
constexpr wchar_t kTrayExitLabel[] = L"\u9000\u51FA\u4E91\u5377";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    // Each preview sub-window owns a separate Flutter engine, so register the
    // same plugins there before Dart tries to use window and image services.
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(flutter_view_controller->engine());
  });
  RegisterWindowChannel();
  InitializeTrayIcon();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Guard against the window being closed before the first frame lands, which
    // would dereference a torn-down window from the engine's frame callback.
    if (GetHandle() != nullptr) {
      EnsureVisible();
    }
  });

  // Some sessions on Windows never receive the SetNextFrameCallback invocation
  // (e.g. the engine restored a cached surface or the callback raced the very
  // first frame). Always show the host window explicitly as a safety net so the
  // app never boots into a hidden window that the user can only reach via tray.
  EnsureVisible();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (window_channel_) {
    window_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kTrayIconMessage:
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          return 0;
        case WM_CONTEXTMENU: {
          POINT anchor = {};
          anchor.x = GET_X_LPARAM(wparam);
          anchor.y = GET_Y_LPARAM(wparam);
          if (anchor.x == -1 && anchor.y == kTrayMenuAnchorBottom) {
            GetCursorPos(&anchor);
          }
          ShowTrayContextMenu(anchor);
          return 0;
        }
        // NOTE: WM_RBUTTONUP/WM_RBUTTONDOWN are intentionally NOT handled
        // here. With NOTIFYICON_VERSION_4 the shell already posts a single
        // WM_CONTEXTMENU for right-clicks; handling the button messages too
        // causes the context menu to appear twice / on the down-click.
      }
      break;

    case WM_COMMAND:
      if (HandleTrayCommand(LOWORD(wparam))) {
        return 0;
      }
      break;

    case WM_CLOSE:
      // Route every OS close gesture through Flutter. Flutter either hides to
      // tray or awaits mount cleanup before calling native ExitApplication.
      if (window_channel_) {
        CloseViaChannel();
        return 0;
      }
      break;

    case WM_SIZE: {
      const LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      if (flutter_controller_ && wparam != SIZE_MINIMIZED) {
        // Present a frame for the new surface promptly during maximize/restore.
        flutter_controller_->ForceRedraw();
      }
      return result;
    }

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterWindowChannel() {
  auto messenger = flutter_controller_->engine()->messenger();
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "remote_storage/window_controls",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "minimize") {
          Minimize();
          result->Success();
          return;
        }
        if (method == "toggleMaximize") {
          MaximizeOrRestore();
          result->Success(flutter::EncodableValue(IsWindowMaximized()));
          return;
        }
        if (method == "close") {
          Close();
          result->Success();
          return;
        }
        if (method == "exitApp") {
          result->Success();
          ExitApplication();
          return;
        }
        if (method == "hideToTray") {
          HideToTray();
          result->Success();
          return;
        }
        if (method == "hideForExit") {
          HideForExit();
          result->Success();
          return;
        }
        if (method == "startDrag") {
          StartDrag();
          result->Success();
          return;
        }
        if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsWindowMaximized()));
          return;
        }
        if (method == "shouldConfirmClose") {
          // When the tray icon is active the host intercepts WM_CLOSE so
          // Alt+F4 / taskbar close also surface the "hide to tray vs exit"
          // prompt; without the tray the in-app close button just quits.
          result->Success(flutter::EncodableValue(tray_icon_added_));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::CloseViaChannel() {
  // Reuse the Flutter close path so every close gesture reaches mount cleanup
  // before the Dart side chooses tray/minimize/exit.
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "requestClose", std::make_unique<flutter::EncodableValue>());
  }
}

void FlutterWindow::ExitViaChannel() {
  // Tray Exit is already an explicit user choice; let Flutter run the same
  // mount cleanup as the title-bar confirmation before destroying the window.
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "requestExit", std::make_unique<flutter::EncodableValue>());
  } else {
    ExitApplication();
  }
}

void FlutterWindow::ExitApplication() {
  // User confirmation has already happened in Flutter; destroy directly so
  // the tray WM_CLOSE interception cannot reopen the confirmation dialog.
  Destroy();
}

void FlutterWindow::InitializeTrayIcon() {
  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(tray_icon_data_.szTip, kTrayTooltip, _TRUNCATE);

  if (Shell_NotifyIcon(NIM_ADD, &tray_icon_data_)) {
    tray_icon_added_ = true;
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_data_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
    tray_icon_added_ = false;
  }
}

void FlutterWindow::HideToTray() {
  // Remember the maximized state before hiding so RestoreFromTray can bring the
  // window back in the exact same shape. Without this, a hidden window would
  // lose track of whether it used to fill the work area.
  was_maximized_before_hide_ = IsWindowMaximized();
  ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::HideForExit() {
  ShowWindow(GetHandle(), SW_HIDE);
  RemoveTrayIcon();
}

void FlutterWindow::RestoreFromTray() {
  // SW_RESTORE only transitions a window out of the minimized/maximized state.
  // It is a no-op for a window that was hidden via SW_HIDE, so the tray click
  // path must explicitly SW_SHOW first. Restoring from tray then re-applies the
  // remembered maximized state when applicable. Without this, clicking the tray
  // icon after "hide to tray" would never bring the main window back.
  if (was_maximized_before_hide_) {
    ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
  } else {
    ShowWindow(GetHandle(), SW_SHOWNORMAL);
  }
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::EnsureVisible() {
  // Centralized "make sure the host window is on screen" helper. Covers both
  // the first-frame startup path and any future restore-from-hidden flow so we
  // never end up with a tray-only app after a relaunch.
  const HWND handle = GetHandle();
  if (handle == nullptr) {
    return;
  }
  ShowWindow(handle, SW_SHOWNORMAL);
  SetForegroundWindow(handle);
}

void FlutterWindow::ShowTrayContextMenu(POINT anchor) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  AppendMenu(menu, MF_STRING, kTrayCommandShow, kTrayShowLabel);
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayCommandExit, kTrayExitLabel);

  SetForegroundWindow(GetHandle());
  const UINT clicked = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, anchor.x, anchor.y,
      0, GetHandle(), nullptr);
  DestroyMenu(menu);

  if (clicked != 0) {
    HandleTrayCommand(clicked);
  }

  // TrackPopupMenu on a notification icon needs a follow-up message so the
  // shell can fully dismiss the temporary menu loop after right-click.
  PostMessage(GetHandle(), WM_NULL, 0, 0);
}

bool FlutterWindow::HandleTrayCommand(UINT command_id) {
  switch (command_id) {
    case kTrayCommandShow:
      RestoreFromTray();
      return true;
    case kTrayCommandExit:
      ExitViaChannel();
      return true;
    default:
      return false;
  }
}
