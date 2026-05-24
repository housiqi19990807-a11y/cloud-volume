// Typed API helpers keep the Flutter pages focused on behavior instead of JSON plumbing.

import 'package:remote_storage/bridge/remote_storage_bridge.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';

abstract class RemoteStorageGateway {
  Future<BootstrapState> loadBootstrapState();
  Future<BootstrapState> saveConfig(RemoteStorageConfig config);
  Future<RemoteStorageConfig> loadProfile(String name);
  Future<List<ProfileInfo>> listProfiles();
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config);
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  );
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
  );
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
  );
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

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async {
    final result = _bridge.call('load_profile', <String, dynamic>{
      'name': name,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ProfileInfo>> listProfiles() async {
    final result = _bridge.call('list_profiles');
    if (result is List) {
      return result
          .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async {
    final result = _bridge.call('list_buckets', <String, dynamic>{
      'config': config.toJson(),
    });
    return _parseList(result, (m) => BucketInfo.fromJson(m));
  }

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async {
    final result = _bridge.call('list_objects', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'prefix': prefix,
    });
    return _parseList(result, (m) => ObjectInfo.fromJson(m));
  }

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
  ) async {
    _bridge.call('upload_file', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'localPath': localPath,
    });
  }

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
  ) async {
    _bridge.call('download_file', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'localPath': localPath,
    });
  }

  List<T> _parseList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (result is List) {
      return result.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
