part of 'remote_storage_api_desktop.dart';

// Runtime info bridge calls: build info, app install, etc.
mixin _RemoteStorageRuntimeApiMixin implements RemoteStorageGateway {
  RemoteStorageBridge get bridgeHandle;
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);

  @override
  Future<String> installApp({
    required String assetUrl,
    required String assetName,
    required String installerType,
    required String mirrorPrefix,
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  }) async {
    final result = await runBridgeCall('install_app', <String, dynamic>{
      'assetUrl': assetUrl,
      'assetName': assetName,
      'installerType': installerType,
      'mirrorPrefix': mirrorPrefix,
      'proxyMode': proxyMode,
      'proxyType': proxyType,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'proxyUsername': proxyUsername,
      'proxyPassword': proxyPassword,
    }) as Map<String, dynamic>;
    return (result['taskId'] ?? '').toString();
  }
}
