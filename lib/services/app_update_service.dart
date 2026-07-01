// 应用更新服务：从 GitHub Releases 读取最新版本，并集中处理版本号比较。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:remote_storage/services/update_settings.dart';
import 'package:remote_storage/services/proxy_http_client.dart';
import 'package:remote_storage/utils/app_runtime_version.dart';

const String kAppLatestReleaseApiUrl =
    'https://api.github.com/repos/lfhy/cloud-volume/releases/latest';
const String kAppLatestReleasePageUrl =
    'https://github.com/lfhy/cloud-volume/releases/latest';

/// Metadata for a single downloadable asset attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.contentType = '',
  });

  /// Asset file name, e.g. `yunjuan-macos-universal.dmg`.
  final String name;

  /// Browser/HTTPS download URL provided by GitHub.
  final String downloadUrl;

  /// File size in bytes.
  final int size;

  /// MIME type reported by GitHub (may be `application/octet-stream`).
  final String contentType;

  @override
  String toString() => 'ReleaseAsset($name, ${size}B)';
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    required this.assets,
    required this.updateAvailable,
    required this.comparable,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseUrl;
  final bool updateAvailable;
  final bool comparable;

  /// All downloadable assets attached to this release.
  final List<ReleaseAsset> assets;
}

class AppUpdateService {
  AppUpdateService({http.Client? client})
    : _client = client ?? createProxyHttpClient(const ProxyConfig()),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Returns a client configured for the given proxy settings.
  /// Falls back to the injected/default client when the proxy is system mode.
  http.Client _clientForProxy(ProxyConfig config) {
    if (config.mode == kProxyModeSystem || config.mode.isEmpty) {
      return _client;
    }
    return createProxyHttpClient(config);
  }

  Future<AppUpdateCheckResult> checkLatestRelease({
    String currentVersion = kAppRuntimeVersion,
    UpdateNetworkConfig networkConfig = const UpdateNetworkConfig(),
    ProxyConfig proxyConfig = const ProxyConfig(),
  }) async {
    // Rebuild the HTTP client if a non-default proxy config is given so runtime
    // changes to the proxy settings take effect immediately.
    final client = _clientForProxy(proxyConfig);
    final apiUrl = networkConfig.wrapUrl(kAppLatestReleaseApiUrl);
    final response = await client
        .get(
          Uri.parse(apiUrl),
          headers: const <String, String>{
            'accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppUpdateException('GitHub 返回 HTTP ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw const AppUpdateException('GitHub 返回内容格式不正确');
    }

    final latestVersion = payload['tag_name']?.toString().trim() ?? '';
    if (latestVersion.isEmpty) {
      throw const AppUpdateException('GitHub Release 缺少版本号');
    }

    final releaseUrl =
        payload['html_url']?.toString().trim() ?? kAppLatestReleasePageUrl;
    final releaseName = payload['name']?.toString().trim() ?? latestVersion;
    final comparison = compareVersionLabels(currentVersion, latestVersion);

    // Parse the `assets` array so the updater can locate the correct
    // platform-specific package for in-app download + install.
    final rawAssets = payload['assets'];
    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final asset in rawAssets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name']?.toString() ?? '';
        final url = asset['browser_download_url']?.toString() ?? '';
        if (name.isEmpty || url.isEmpty) continue;
        assets.add(ReleaseAsset(
          name: name,
          downloadUrl: url,
          size: (asset['size'] as num?)?.toInt() ?? 0,
          contentType: asset['content_type']?.toString() ?? '',
        ));
      }
    }

    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseName: releaseName.isEmpty ? latestVersion : releaseName,
      releaseUrl: releaseUrl.isEmpty ? kAppLatestReleasePageUrl : releaseUrl,
      assets: assets,
      updateAvailable: comparison != null && comparison < 0,
      comparable: comparison != null,
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

int? compareVersionLabels(String currentVersion, String latestVersion) {
  final current = _ParsedVersion.tryParse(currentVersion);
  final latest = _ParsedVersion.tryParse(latestVersion);
  if (current == null || latest == null) {
    return null;
  }
  return current.compareTo(latest);
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  const _ParsedVersion({required this.core, required this.prerelease});

  final List<int> core;
  final List<String> prerelease;

  static _ParsedVersion? tryParse(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (normalized.isEmpty) {
      return null;
    }
    final withoutBuild = normalized.split('+').first;
    final pieces = withoutBuild.split('-');
    final coreParts = pieces.first.split('.');
    if (coreParts.isEmpty) {
      return null;
    }
    final core = <int>[];
    for (final part in coreParts) {
      if (part.isEmpty || int.tryParse(part) == null) {
        return null;
      }
      core.add(int.parse(part));
    }
    return _ParsedVersion(
      core: core,
      prerelease: pieces.length > 1
          ? pieces.sublist(1).join('-').split('.')
          : const <String>[],
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    final width = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var index = 0; index < width; index += 1) {
      final left = index < core.length ? core[index] : 0;
      final right = index < other.core.length ? other.core[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }
    return _comparePrerelease(other);
  }

  int _comparePrerelease(_ParsedVersion other) {
    if (prerelease.isEmpty && other.prerelease.isEmpty) {
      return 0;
    }
    if (prerelease.isEmpty) {
      return 1;
    }
    if (other.prerelease.isEmpty) {
      return -1;
    }
    final width = prerelease.length > other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < width; index += 1) {
      if (index >= prerelease.length) {
        return -1;
      }
      if (index >= other.prerelease.length) {
        return 1;
      }
      final left = prerelease[index];
      final right = other.prerelease[index];
      if (left == right) {
        continue;
      }
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }
      return left.compareTo(right);
    }
    return 0;
  }
}
