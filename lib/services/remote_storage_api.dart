// Typed API helpers keep the Flutter pages focused on behavior instead of JSON plumbing.

import 'dart:isolate';

import 'package:remote_storage/bridge/remote_storage_bridge.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/transfer_job.dart';

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
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  );
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  );
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
  );
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName,
  );
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  );
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  );
  Future<void> cancelTransfer(String taskId);
  Future<List<TransferSnapshot>> listTransferJobs();
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
  );
  Future<BucketMountStatus> unmountBucket(String bucket);
  Future<BucketMountStatus> getBucketMountStatus(String bucket);
  Future<BucketMountStatus> openBucketMount(String bucket);
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
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async {
    final result = _bridge.call('head_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
    });
    return ObjectInfo.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  ) async {
    _bridge.call('create_directory', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'prefix': prefix,
      'name': name,
    });
  }

  @override
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
  ) async {
    _bridge.call('delete_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'isDirectory': isDirectory,
    });
  }

  @override
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName,
  ) async {
    _bridge.call('rename_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'isDirectory': isDirectory,
      'newName': newName,
    });
  }

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('upload_file', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'key': key,
        'localPath': localPath,
        'taskId': taskId,
      });
    });
  }

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('download_file', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'key': key,
        'localPath': localPath,
        'taskId': taskId,
      });
    });
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    _bridge.call('cancel_transfer', <String, dynamic>{'taskId': taskId});
  }

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async {
    final result = _bridge.call('list_transfer_jobs');
    return _parseList(result, (m) => TransferSnapshot.fromJson(m));
  }

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    final result = _bridge.call('mount_bucket', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> unmountBucket(String bucket) async {
    final result = _bridge.call('unmount_bucket', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async {
    final result = _bridge.call('get_bucket_mount_status', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async {
    final result = _bridge.call('open_bucket_mount', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
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
