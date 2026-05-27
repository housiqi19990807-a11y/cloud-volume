part of 'remote_storage_api.dart';

// Share bridge calls stay on a dedicated mixin so the main API file stays small.
mixin _RemoteStorageShareApiMixin implements RemoteStorageGateway {
  RemoteStorageBridge get bridgeHandle;
  List<T> parseBridgeList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  );

  @override
  Future<ShareRecord> createShare(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String name,
    int durationSec,
  ) async {
    final result = await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(bridgeHandle.libraryPath);
      return bridge.call('create_share', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'key': key,
        'name': name,
        'durationSec': durationSec,
      });
    });
    return ShareRecord.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ShareRecord>> listShares(RemoteStorageConfig config) async {
    final result = await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(bridgeHandle.libraryPath);
      return bridge.call('list_shares', <String, dynamic>{
        'config': config.toJson(),
      });
    });
    return parseBridgeList(result, (m) => ShareRecord.fromJson(m));
  }

  @override
  Future<ShareRecord> refreshShare(
    RemoteStorageConfig config,
    String id,
    int durationSec,
  ) async {
    final result = await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(bridgeHandle.libraryPath);
      return bridge.call('refresh_share', <String, dynamic>{
        'config': config.toJson(),
        'id': id,
        'durationSec': durationSec,
      });
    });
    return ShareRecord.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> deleteShare(RemoteStorageConfig config, String id) async {
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(bridgeHandle.libraryPath);
      bridge.call('delete_share', <String, dynamic>{
        'config': config.toJson(),
        'id': id,
      });
    });
  }
}
