// Typed API helpers keep the Flutter pages focused on behavior instead of JSON plumbing.

import 'package:remote_storage/bridge/remote_storage_bridge.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';

abstract class RemoteStorageGateway {
  Future<BootstrapState> loadBootstrapState();

  Future<BootstrapState> saveConfig(RemoteStorageConfig config);
}

typedef RemoteStorageApiFactory = Future<RemoteStorageGateway> Function();

Future<RemoteStorageGateway> defaultRemoteStorageApiFactory() {
  return RemoteStorageApi.bootstrap();
}

class RemoteStorageApi implements RemoteStorageGateway {
  RemoteStorageApi(this._bridge);

  static Future<RemoteStorageApi> bootstrap() async {
    final bridge = await RemoteStorageBridge.connect();
    return RemoteStorageApi(bridge);
  }

  final RemoteStorageBridge _bridge;

  @override
  Future<BootstrapState> loadBootstrapState() async {
    final payload =
        _bridge.call('load_bootstrap_state') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    final payload =
        _bridge.call('save_config', <String, dynamic>{
              'config': config.toJson(),
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }
}
