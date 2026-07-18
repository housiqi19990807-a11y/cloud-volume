// The public Windows entry point launches and watches the Flutter process so
// failures before the first window exists can still produce a crash report.
#include <windows.h>

#include <filesystem>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kAppExecutableName[] = L"cloud-volume-app.exe";
constexpr wchar_t kReporterExecutableName[] =
    L"cloud-volume-crash-reporter.exe";

std::filesystem::path ExecutableDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return {};
    }
    if (length < buffer.size() - 1) {
      return std::filesystem::path(buffer.data()).parent_path();
    }
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring QuoteArgument(const std::wstring& value) {
  std::wstring quoted = L"\"";
  size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      backslashes++;
      continue;
    }
    if (character == L'\"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(character);
      backslashes = 0;
      continue;
    }
    quoted.append(backslashes, L'\\');
    backslashes = 0;
    quoted.push_back(character);
  }
  quoted.append(backslashes * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

bool StartCrashReporter(const std::filesystem::path& directory,
                        const std::filesystem::path& app_path,
                        DWORD child_pid,
                        DWORD exit_code,
                        DWORD launch_error) {
  const std::filesystem::path reporter_path =
      directory / kReporterExecutableName;
  std::wstring command = QuoteArgument(reporter_path.wstring()) +
                         L" --exe " + QuoteArgument(app_path.wstring()) +
                         L" --pid " + std::to_wstring(child_pid);
  if (launch_error != ERROR_SUCCESS) {
    command += L" --launch-error " + std::to_wstring(launch_error);
  } else {
    command += L" --exit-code " + std::to_wstring(exit_code);
  }

  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info = {};
  if (!::CreateProcessW(reporter_path.c_str(), mutable_command.data(), nullptr,
                        nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                        directory.c_str(), &startup_info, &process_info)) {
    return false;
  }
  ::CloseHandle(process_info.hThread);
  ::CloseHandle(process_info.hProcess);
  return true;
}

void ShowFallbackError(DWORD exit_code, DWORD launch_error) {
  std::wstring detail;
  if (launch_error != ERROR_SUCCESS) {
    detail = L"Windows 无法启动云卷主程序。错误码：" +
             std::to_wstring(launch_error);
  } else {
    wchar_t code[16] = {};
    swprintf_s(code, L"0x%08lX", exit_code);
    detail = L"云卷主程序异常退出。退出码：" + std::wstring(code);
  }
  detail += L"\n\n崩溃报告器也未能启动，请将此错误码提交给开发者。";
  ::MessageBoxW(nullptr, detail.c_str(), L"云卷启动失败",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE previous,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  const std::filesystem::path directory = ExecutableDirectory();
  const std::filesystem::path app_path = directory / kAppExecutableName;
  std::wstring child_command = QuoteArgument(app_path.wstring());
  if (command_line != nullptr && command_line[0] != L'\0') {
    child_command += L" ";
    child_command += command_line;
  }

  std::vector<wchar_t> mutable_command(child_command.begin(),
                                       child_command.end());
  mutable_command.push_back(L'\0');
  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.wShowWindow = static_cast<WORD>(show_command);
  PROCESS_INFORMATION process_info = {};
  if (!::CreateProcessW(app_path.c_str(), mutable_command.data(), nullptr,
                        nullptr, FALSE, 0, nullptr, directory.c_str(),
                        &startup_info, &process_info)) {
    const DWORD launch_error = ::GetLastError();
    if (!StartCrashReporter(directory, app_path, 0, 0, launch_error)) {
      ShowFallbackError(0, launch_error);
    }
    return EXIT_FAILURE;
  }

  ::CloseHandle(process_info.hThread);
  ::WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD exit_code = EXIT_FAILURE;
  ::GetExitCodeProcess(process_info.hProcess, &exit_code);
  ::CloseHandle(process_info.hProcess);

  if (exit_code != EXIT_SUCCESS &&
      !StartCrashReporter(directory, app_path, process_info.dwProcessId,
                          exit_code, ERROR_SUCCESS)) {
    ShowFallbackError(exit_code, ERROR_SUCCESS);
  }
  return exit_code == EXIT_SUCCESS ? EXIT_SUCCESS : EXIT_FAILURE;
}
