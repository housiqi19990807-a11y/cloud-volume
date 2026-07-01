// Matches the correct platform-specific release asset from a GitHub release.
// Asset naming follows the pattern `yunjuan-<platform>-<arch>.<ext>`.

import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/app_update_service.dart';

/// Describes which asset to download and how to install it on this platform.
class PlatformUpdateAsset {
  const PlatformUpdateAsset({
    required this.asset,
    required this.platform,
    required this.installerType,
  });

  final ReleaseAsset asset;

  /// Human-readable platform label for UI display.
  final String platform;

  /// How the package should be installed (`dmg`, `zip`, `exe`, `tarball`, `appimage`).
  final String installerType;

  @override
  String toString() => 'PlatformUpdateAsset(${asset.name}, $installerType)';
}

/// Returns the best-matching asset for the current runtime platform, or `null`
/// if no suitable package is found in the release.
PlatformUpdateAsset? matchPlatformAsset(List<ReleaseAsset> assets) {
  if (assets.isEmpty) return null;

  if (isMacOSPlatform) {
    return _matchMacOS(assets);
  }
  if (isWindowsPlatform) {
    return _matchWindows(assets);
  }
  if (isLinuxPlatform) {
    return _matchLinux(assets);
  }
  return null;
}

PlatformUpdateAsset? _matchMacOS(List<ReleaseAsset> assets) {
  // Preference order: universal DMG > universal zip > arm64 DMG > arm64 zip.
  // On Apple Silicon we prefer universal; on Intel we fall back to arm64-less.
  const priorities = [
    ['macos-universal', '.dmg'],
    ['macos-universal', '.zip'],
    ['macos-arm64', '.dmg'],
    ['macos-arm64', '.zip'],
    ['macos-amd64', '.dmg'],
    ['macos-amd64', '.zip'],
  ];
  for (final spec in priorities) {
    final match = _findAsset(assets, spec[0], spec[1]);
    if (match != null) {
      final isDmg = spec[1] == '.dmg';
      return PlatformUpdateAsset(
        asset: match,
        platform: 'macOS',
        installerType: isDmg ? 'dmg' : 'zip',
      );
    }
  }
  return null;
}

PlatformUpdateAsset? _matchWindows(List<ReleaseAsset> assets) {
  // Prefer the Inno Setup installer; fall back to zip.
  const installerPattern = 'windows-amd64-installer';
  final installer = assets.cast<ReleaseAsset?>().firstWhere(
    (a) => a!.name.toLowerCase().contains(installerPattern) &&
        a.name.toLowerCase().endsWith('.exe'),
    orElse: () => null,
  );
  if (installer != null) {
    return PlatformUpdateAsset(
      asset: installer,
      platform: 'Windows',
      installerType: 'exe',
    );
  }
  final zip = _findAsset(assets, 'windows-amd64', '.zip');
  if (zip != null) {
    return PlatformUpdateAsset(
      asset: zip,
      platform: 'Windows',
      installerType: 'zip',
    );
  }
  return null;
}

PlatformUpdateAsset? _matchLinux(List<ReleaseAsset> assets) {
  // Prefer AppImage; fall back to tarball.
  final appimage = _findAsset(assets, 'linux-amd64', '.appimage');
  if (appimage != null) {
    return PlatformUpdateAsset(
      asset: appimage,
      platform: 'Linux',
      installerType: 'appimage',
    );
  }
  final tarball = _findAsset(assets, 'linux-amd64', '.tar.gz');
  if (tarball != null) {
    return PlatformUpdateAsset(
      asset: tarball,
      platform: 'Linux',
      installerType: 'tarball',
    );
  }
  return null;
}

ReleaseAsset? _findAsset(
  List<ReleaseAsset> assets,
  String nameFragment,
  String extension,
) {
  final lowered = nameFragment.toLowerCase();
  final ext = extension.toLowerCase();
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (name.contains(lowered) && name.endsWith(ext)) {
      return asset;
    }
  }
  return null;
}
