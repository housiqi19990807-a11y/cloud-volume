// Local file opener delegates to the desktop shell so cached files open natively.

import 'dart:io';

class LocalFileOpener {
  const LocalFileOpener._();

  static Future<void> openPath(String filePath) async {
    final command = _commandFor(filePath);
    final result = await Process.run(command.executable, command.arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        command.executable,
        command.arguments,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  static _ShellCommand _commandFor(String filePath) {
    if (Platform.isMacOS) {
      return _ShellCommand('open', <String>[filePath]);
    }
    if (Platform.isLinux) {
      return _ShellCommand('xdg-open', <String>[filePath]);
    }
    if (Platform.isWindows) {
      return _ShellCommand('cmd', <String>['/c', 'start', '', filePath]);
    }
    throw UnsupportedError('当前平台暂不支持直接打开本地文件');
  }
}

class _ShellCommand {
  const _ShellCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
