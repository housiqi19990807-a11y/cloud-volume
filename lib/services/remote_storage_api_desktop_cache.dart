part of 'remote_storage_api_desktop.dart';

// Cache bridge calls cover settings cleanup and preview-cache index persistence.
mixin _RemoteStorageCacheApiMixin implements RemoteStorageGateway {
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);

  @override
  Future<CacheStats> getCacheStats(RemoteStorageConfig config) async {
    final result = await runBridgeCall('get_cache_stats', <String, dynamic>{
      'config': config.toJson(),
    });
    return CacheStats.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> openCacheDirectory(RemoteStorageConfig config) async {
    await runBridgeCall('open_cache_directory', <String, dynamic>{
      'config': config.toJson(),
    });
  }

  @override
  Future<CleanCacheResult> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  }) async {
    final result = await runBridgeCall('clean_cache', <String, dynamic>{
      'config': config.toJson(),
      'clearAll': clearAll,
    });
    return CleanCacheResult.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<CachedFileRecord?> findCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async {
    final result = await runBridgeCall('cache_index_find', <String, dynamic>{
      'bucket': bucket,
      'objectKey': objectKey,
    });
    if (result is! Map<String, dynamic>) {
      return null;
    }
    return CachedFileRecord.fromJson(result);
  }

  @override
  Future<void> upsertCacheIndexRecord(CachedFileRecord record) async {
    await runBridgeCall('cache_index_upsert', <String, dynamic>{
      'record': record.toJson(),
    });
  }

  @override
  Future<void> removeCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async {
    await runBridgeCall('cache_index_remove', <String, dynamic>{
      'bucket': bucket,
      'objectKey': objectKey,
    });
  }

  @override
  Future<List<CachedFileRecord>> removeCacheIndexPrefix({
    required String bucket,
    required String objectKeyPrefix,
  }) async {
    final result = await runBridgeCall(
      'cache_index_remove_prefix',
      <String, dynamic>{'bucket': bucket, 'objectKeyPrefix': objectKeyPrefix},
    );
    if (result is! List) {
      return <CachedFileRecord>[];
    }
    return result
        .map((item) => CachedFileRecord.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
