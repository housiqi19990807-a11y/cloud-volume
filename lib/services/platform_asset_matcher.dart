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

  /// Reconstructs from the Go bridge `match_platform_asset` response, or null
  /// when the payload is absent (no match or bridge unavailable).
  static PlatformUpdateAsset? fromBridgeJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final assetJson = json['asset'] as Map<String, dynamic>?;
    if (assetJson == null) return null;
    return PlatformUpdateAsset(
      asset: ReleaseAsset(
        name: assetJson['name'] as String? ?? '',
        downloadUrl: assetJson['downloadUrl'] as String? ?? '',
        size: assetJson['size'] as int? ?? 0,
        contentType: assetJson['contentType'] as String? ?? '',
        digest: assetJson['digest'] as String? ?? '',
      ),
      platform: json['platform'] as String? ?? '',
      installerType: json['installerType'] as String? ?? '',
    );
  }
}

/// Returns the best-matching asset for the current runtime platform, or `null`
/// if no suitable package is found in the release.
PlatformUpdateAsset? matchPlatformAsset(
  List<ReleaseAsset> assets, {
  String? runtimeArchitecture,
}) {
  if (assets.isEmpty) return null;

  if (isMacOSPlatform) {
    return _matchMacOS(assets, runtimeArchitecture ?? runtimeCpuArchitecture);
  }
  if (isWindowsPlatform) {
    return _matchWindows(assets);
  }
  if (isLinuxPlatform) {
    return _matchLinux(assets);
  }
  return null;
}

PlatformUpdateAsset? _matchMacOS(List<ReleaseAsset> assets, String arch) {
  final preferredArch = arch == 'arm64' || arch == 'amd64' ? arch : '';
  final fallbackArch = preferredArch == 'arm64' ? 'amd64' : 'arm64';
  final priorities = <List<String>>[
    if (preferredArch.isNotEmpty) ...[
      ['macos-$preferredArch', '.dmg'],
      ['macos-$preferredArch', '.zip'],
    ],
    ['macos-universal', '.dmg'],
    ['macos-universal', '.zip'],
    if (preferredArch.isNotEmpty) ...[
      ['macos-$fallbackArch', '.dmg'],
      ['macos-$fallbackArch', '.zip'],
    ] else ...[
      ['macos-arm64', '.dmg'],
      ['macos-arm64', '.zip'],
      ['macos-amd64', '.dmg'],
      ['macos-amd64', '.zip'],
    ],
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
  // Prefer the green ZIP package; fall back to the Inno Setup installer.
  final zip = _findAsset(assets, 'windows-amd64', '.zip');
  if (zip != null) {
    return PlatformUpdateAsset(
      asset: zip,
      platform: 'Windows',
      installerType: 'zip',
    );
  }
  const installerPattern = 'windows-amd64-installer';
  final installer = assets.cast<ReleaseAsset?>().firstWhere(
    (a) =>
        a!.name.toLowerCase().contains(installerPattern) &&
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
