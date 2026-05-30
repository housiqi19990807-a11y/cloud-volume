#include <algorithm>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr unsigned int kDefaultWindowWidth = 1120;
constexpr unsigned int kDefaultWindowHeight = 700;
constexpr unsigned int kMinimumWindowWidth = 920;
constexpr unsigned int kMinimumWindowHeight = 600;
constexpr unsigned int kCompactFallbackWindowWidth = 820;
constexpr unsigned int kCompactFallbackWindowHeight = 560;

// Keep the Windows startup window slightly tighter than before so large and
// mid-sized displays do not open an overly wide first-run layout.
Win32Window::Size ResolveInitialWindowSize() {
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  const HMONITOR monitor = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  if (monitor == nullptr || !GetMonitorInfo(monitor, &monitor_info)) {
    return Win32Window::Size(kDefaultWindowWidth, kDefaultWindowHeight);
  }

  const LONG work_width = monitor_info.rcWork.right - monitor_info.rcWork.left;
  const LONG work_height = monitor_info.rcWork.bottom - monitor_info.rcWork.top;
  if (work_width <= 0 || work_height <= 0) {
    return Win32Window::Size(kDefaultWindowWidth, kDefaultWindowHeight);
  }

  const unsigned int width_floor = std::min(
      kMinimumWindowWidth,
      std::max(
          kCompactFallbackWindowWidth, static_cast<unsigned int>(work_width - 32)));
  const unsigned int height_floor = std::min(
      kMinimumWindowHeight,
      std::max(kCompactFallbackWindowHeight,
          static_cast<unsigned int>(work_height - 32)));
  const unsigned int width_ceiling =
      static_cast<unsigned int>(work_width * 68 / 100);
  const unsigned int height_ceiling =
      static_cast<unsigned int>(work_height * 64 / 100);
  const unsigned int resolved_width = std::min(
      kDefaultWindowWidth, std::max(width_floor, width_ceiling));
  const unsigned int resolved_height = std::min(
      kDefaultWindowHeight, std::max(height_floor, height_ceiling));
  return Win32Window::Size(resolved_width, resolved_height);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size = ResolveInitialWindowSize();
  if (!window.Create(L"Yunjuan", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
