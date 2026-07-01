// 应用更新网络配置：管理 GitHub 加速镜像前缀和 HTTP 代理地址。
// 镜像配置持久化到 SharedPreferences，供更新检查和下载安装流程读取。
// 全局代理配置由 Go config 管理（proxyMode / proxyUrl），这里只负责 GitHub 镜像。

import 'package:shared_preferences/shared_preferences.dart';

/// Pref keys.
const String kUpdateMirrorKey = 'update.mirror_prefix';

/// Known public GitHub acceleration mirrors (China-friendly).
/// `ghProxy` wraps any github.com URL as `https://gh-proxy.com/<original>`.
const List<String> kKnownMirrors = [
  '',
  'https://gh-proxy.com',
  'https://ghfast.top',
];

class UpdateNetworkConfig {
  const UpdateNetworkConfig({
    this.mirrorPrefix = '',
  });

  /// Mirror prefix prepended to GitHub URLs (e.g. `https://gh-proxy.com`).
  /// Empty string means direct connection (no mirror).
  final String mirrorPrefix;

  bool get hasMirror => mirrorPrefix.isNotEmpty;

  UpdateNetworkConfig copyWith({String? mirrorPrefix, String? proxyUrl}) {
    return UpdateNetworkConfig(
      mirrorPrefix: mirrorPrefix ?? this.mirrorPrefix,
    );
  }

  /// Wraps a GitHub URL with the configured mirror prefix.
  /// e.g. `https://github.com/...` → `https://gh-proxy.com/https://github.com/...`
  /// Also handles `api.github.com` URLs.
  String wrapUrl(String url) {
    if (!hasMirror) return url;
    final prefix = mirrorPrefix.endsWith('/')
        ? mirrorPrefix.substring(0, mirrorPrefix.length - 1)
        : mirrorPrefix;
    return '$prefix/$url';
  }
}

/// Loads the persisted GitHub mirror config.
Future<UpdateNetworkConfig> loadUpdateNetworkConfig() async {
  final prefs = await SharedPreferences.getInstance();
  return UpdateNetworkConfig(
    mirrorPrefix: prefs.getString(kUpdateMirrorKey) ?? '',
  );
}

/// Saves the GitHub mirror config to SharedPreferences.
Future<void> saveUpdateNetworkConfig(UpdateNetworkConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kUpdateMirrorKey, config.mirrorPrefix);
}
