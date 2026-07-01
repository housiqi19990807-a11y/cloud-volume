// Desktop installer: downloads the release asset to a temp directory, then
// launches a platform-specific install + relaunch sequence.
//
// macOS:   Mounts the DMG, replaces /Applications/云卷.app, strips quarantine.
// Windows: Runs the Inno Setup installer with /SILENT /CLOSEAPPLICATIONS.
// Linux:   Extracts the tarball to the install prefix, or replaces the AppImage.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/app_update_service.dart';

const bool kSupportsInAppInstall = true;

/// Downloads [asset] to a temp file, then installs it on the current platform.
///
/// [onProgress] receives `(bytesReceived, totalBytes)` during download.
/// Returns `null` on success, or a human-readable error string on failure.
Future<String?> downloadAndInstallAsset(
  ReleaseAsset asset,
  String installerType, {
  void Function(int received, int total)? onProgress,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final downloadPath = p.join(tempDir.path, asset.name);
    final file = File(downloadPath);

    // Download with streaming to report progress.
    final request = http.Request('GET', Uri.parse(asset.downloadUrl));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      return '下载失败：HTTP ${response.statusCode}';
    }
    final total = asset.size > 0 ? asset.size : response.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();

    // Install per platform.
    if (isMacOSPlatform) {
      return await _installMacOS(downloadPath, installerType);
    }
    if (isWindowsPlatform) {
      return await _installWindows(downloadPath, installerType);
    }
    if (isLinuxPlatform) {
      return await _installLinux(downloadPath, installerType);
    }
    return '不支持的平台';
  } catch (e) {
    return '更新失败：$e';
  }
}

// ── macOS ──────────────────────────────────────────────────────────────────

Future<String?> _installMacOS(String downloadPath, String installerType) async {
  final appName = '云卷.app';
  final appsDir = '/Applications';
  final targetApp = p.join(appsDir, appName);

  try {
    if (installerType == 'dmg') {
      // Mount the DMG, copy the .app out, then unmount.
      final mountResult = await Process.run('hdiutil', [
        'attach', '-nobrowse', '-noautoopen', downloadPath,
      ]);
      if (mountResult.exitCode != 0) {
        return '无法挂载 DMG：${mountResult.stderr}';
      }
      // Parse mount point from hdiutil output (last line's last column).
      final lines = (mountResult.stdout as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length < 2) {
        return '无法解析 DMG 挂载点';
      }
      final mountLine = lines.last;
      final parts = mountLine.split('\t');
      final mountPoint = parts.last.trim();
      final mountedApp = p.join(mountPoint, appName);

      if (!await Directory(mountedApp).exists()) {
        await Process.run('hdiutil', ['detach', mountPoint, '-quiet']);
        return 'DMG 内未找到 $appName';
      }

      // Remove old app, copy new one.
      final oldApp = Directory(targetApp);
      if (await oldApp.exists()) {
        await oldApp.delete(recursive: true);
      }
      final copyResult = await Process.run('cp', ['-R', mountedApp, appsDir]);
      // Detach regardless of copy result.
      await Process.run('hdiutil', ['detach', mountPoint, '-quiet']);
      if (copyResult.exitCode != 0) {
        return '复制应用失败：${copyResult.stderr}';
      }
    } else {
      // ZIP: unzip directly to /Applications, replacing old app.
      final oldApp = Directory(targetApp);
      if (await oldApp.exists()) {
        await oldApp.delete(recursive: true);
      }
      final unzipResult = await Process.run('unzip', ['-o', downloadPath, '-d', appsDir]);
      if (unzipResult.exitCode != 0) {
        return '解压失败：${unzipResult.stderr}';
      }
    }

    // Strip quarantine attribute so Gatekeeper doesn't block the new app.
    await Process.run('xattr', ['-cr', targetApp]);

    // Relaunch the new app and quit the current instance.
    final executable = p.join(targetApp, 'Contents', 'MacOS', '云卷');
    await Process.start('open', ['-n', executable], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  } catch (e) {
    return 'macOS 安装失败：$e';
  }
}

// ── Windows ────────────────────────────────────────────────────────────────

Future<String?> _installWindows(String downloadPath, String installerType) async {
  try {
    if (installerType == 'exe') {
      // Inno Setup supports /SILENT /CLOSEAPPLICATIONS /NORESTART /SP-.
      // The installer will close the running app, replace files, and we relaunch.
      await Process.start(
        downloadPath,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/NORESTART', '/SP-', '/NOCANCEL'],
        mode: ProcessStartMode.detached,
      );
      // Give the installer a moment, then exit so it can replace our files.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    }
    // ZIP: not as clean on Windows; instruct the user.
    return '请使用 installer (.exe) 版本进行自动更新';
  } catch (e) {
    return 'Windows 安装失败：$e';
  }
}

// ── Linux ──────────────────────────────────────────────────────────────────

Future<String?> _installLinux(String downloadPath, String installerType) async {
  try {
    if (installerType == 'appimage') {
      // Determine current executable path for self-replacement.
      final currentExe = Platform.resolvedExecutable;
      final targetPath = currentExe.contains('AppRun') ||
              currentExe.endsWith('remote_storage')
          ? currentExe
          : p.join(p.dirname(currentExe), 'yunjuan.AppImage');

      // Try to replace in-place; may need write permission.
      final newFile = File(downloadPath);
      await newFile.copy(targetPath);
      await Process.run('chmod', ['+x', targetPath]);

      await Process.start(targetPath, [], mode: ProcessStartMode.detached);
      exit(0);
    }

    // tarball: extract to the same directory as the current executable.
    final currentExe = Platform.resolvedExecutable;
    final installDir = p.dirname(currentExe);
    final result = await Process.run(
      'tar', ['-xzf', downloadPath, '--strip-components=1', '-C', installDir],
    );
    if (result.exitCode != 0) {
      return '解压失败：${result.stderr}';
    }
    await Process.start(currentExe, [], mode: ProcessStartMode.detached);
    exit(0);
  } catch (e) {
    return 'Linux 安装失败：$e';
  }
}
