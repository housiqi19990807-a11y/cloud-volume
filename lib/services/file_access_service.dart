// File access service owns click-to-open, explicit download, and cache bookkeeping.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_cache_store.dart';
import 'package:remote_storage/services/local_file_opener.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/default_download_directory.dart';

class FileAccessService {
  FileAccessService._();

  static final FileAccessService instance = FileAccessService._();

  final FileCacheStore _cacheStore = FileCacheStore.instance;

  Future<void> openObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final cachedPath = await _cacheStore.findUsableCachePath(bucket, object);
    if (cachedPath != null) {
      await LocalFileOpener.openPath(cachedPath);
      return;
    }

    final cachePath = await _cacheStore.cachePathFor(bucket, object.key);
    final existingTask = TransferQueue.instance.findActiveTask(
      isUpload: false,
      bucket: bucket,
      key: object.key,
      localPath: cachePath,
    );
    if (existingTask != null) {
      return;
    }

    final task = TransferQueue.instance.startTask(
      isUpload: false,
      bucket: bucket,
      key: object.key,
      localPath: cachePath,
    );
    await _runDownload(
      api: api,
      config: config,
      task: task,
      onSuccess: () async {
        await _cacheStore.upsertCacheRecord(
          bucket: bucket,
          object: object,
          localPath: cachePath,
        );
        await LocalFileOpener.openPath(cachePath);
      },
      onFailure: () async {
        await _cacheStore.removeCacheRecord(
          bucket: bucket,
          objectKey: object.key,
          localPath: cachePath,
          deleteFile: true,
        );
      },
    );
  }

  Future<void> downloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final initialDirectory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    final savePath = await FilePicker.saveFile(
      dialogTitle: '下载到',
      fileName: object.displayName,
      initialDirectory: initialDirectory,
    );
    if (savePath == null || savePath.trim().isEmpty) {
      return;
    }

    final task = TransferQueue.instance.startTask(
      isUpload: false,
      bucket: bucket,
      key: object.key,
      localPath: savePath,
    );
    await _runDownload(
      api: api,
      config: config,
      task: task,
      onFailure: () => _deleteFileIfExists(savePath),
    );
  }

  Future<void> evictCacheForObject({
    required String bucket,
    required ObjectInfo object,
  }) async {
    if (object.isDir) {
      await _cacheStore.removeCachePrefix(
        bucket: bucket,
        objectKeyPrefix: object.key,
        deleteFiles: true,
      );
      return;
    }
    await _cacheStore.removeCacheRecord(
      bucket: bucket,
      objectKey: object.key,
      deleteFile: true,
    );
  }

  Future<void> _runDownload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required TransferTask task,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFailure,
  }) async {
    try {
      await api.downloadFile(
        config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
      if (onSuccess != null) {
        await onSuccess();
      }
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      if (onFailure != null) {
        await onFailure();
      }
      if (TransferQueue.instance.statusOf(task.id) == TransferStatus.canceled) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _deleteFileIfExists(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
