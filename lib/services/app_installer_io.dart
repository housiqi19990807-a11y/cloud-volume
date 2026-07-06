// Desktop installer delegates to the Go bridge so all platform-specific
// download + install + relaunch logic runs in Go, not Dart. Flutter renders
// UI state only and polls progress through the TransferQueue.

import 'package:remote_storage/services/app_update_service.dart';
import 'package:remote_storage/services/proxy_http_client.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';

const bool kSupportsInAppInstall = true;

/// Starts the full download + install + relaunch flow in the Go bridge.
///
/// Returns the Go transfer task id. Progress is reported via [TransferQueue]
/// polling, not through [onProgress]. The callback is kept for source
/// compatibility with older call sites and is intentionally unused.
Future<String> downloadAndInstallAsset(
  RemoteStorageGateway api,
  ReleaseAsset asset,
  String installerType, {
  void Function(int received, int total)? onProgress,
  UpdateNetworkConfig networkConfig = const UpdateNetworkConfig(),
  ProxyConfig proxyConfig = const ProxyConfig(),
  RemoteStorageConfig? config,
}) {
	return api.installApp(
		assetUrl: asset.downloadUrl,
		assetName: asset.name,
		assetSize: asset.size,
	assetDigest: asset.digest,
		installerType: installerType,
    mirrorPrefix: networkConfig.mirrorPrefix,
    config: config ?? RemoteStorageConfig.empty(),
    proxyMode: proxyConfig.mode,
    proxyType: proxyConfig.type,
    proxyHost: proxyConfig.host,
    proxyPort: proxyConfig.port,
    proxyUsername: proxyConfig.username,
    proxyPassword: proxyConfig.password,
  );
}
