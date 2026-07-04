// Web stub: in-app self-install is not available in the browser.

import 'package:remote_storage/services/app_update_service.dart';
import 'package:remote_storage/services/proxy_http_client.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';

/// Always `false` on the web platform — there is no local install path.
const bool kSupportsInAppInstall = false;

/// Starts a release-asset install. Web builds cannot self-install.
Future<String> downloadAndInstallAsset(
  RemoteStorageGateway api,
  ReleaseAsset asset,
  String installerType, {
  void Function(int received, int total)? onProgress,
  UpdateNetworkConfig networkConfig = const UpdateNetworkConfig(),
  ProxyConfig proxyConfig = const ProxyConfig(),
  RemoteStorageConfig? config,
}) async {
  throw UnsupportedError('Web 端不支持应用内自动更新，请前往 GitHub 下载。');
}
