// File access service owns click-to-open, explicit download, and cache bookkeeping.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_cache_store.dart';
import 'package:remote_storage/services/file_access_download_cache_io.dart';
import 'package:remote_storage/services/file_access_paths_io.dart';
import 'package:remote_storage/services/file_access_transfer_request.dart';
import 'package:remote_storage/services/local_file_opener.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:path/path.dart' as path;

class FileAccessService {
  FileAccessService._();

  static final FileAccessService instance = FileAccessService._();

  final FileCacheStore _cacheStore = FileCacheStore.instance;

  Future<FilePreviewSource> preparePreviewSource({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final cachePath = await _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    return FilePreviewSource(bytes: await File(cachePath).readAsBytes());
  }

  Future<String> preparePreviewFilePath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  Future<void> openObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final cachePath = await _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    await LocalFileOpener.openPath(cachePath);
  }

  Future<FileAccessTransferRequest> prepareObjectForExternalOpen({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return _ensureCachedObjectRequest(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  Future<void> openLocalPath(String localPath) {
    return LocalFileOpener.openPath(localPath);
  }

  Future<String> _ensureCachedObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final request = await _ensureCachedObjectRequest(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    return request.completion;
  }

  Future<FileAccessTransferRequest> _ensureCachedObjectRequest({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final remoteObject = await api.headObject(config, bucket, object.key);
    final cachedPath = await _cacheStore.findUsableCachePath(
      config.resolvedCacheDirectory,
      bucket,
      remoteObject,
    );
    if (cachedPath != null) {
      return FileAccessTransferRequest(completion: Future.value(cachedPath));
    }

    final cachePath = await _cacheStore.cachePathFor(
      config.resolvedCacheDirectory,
      bucket,
      object.key,
    );
    final existingTask = TransferQueue.instance.findActiveTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: cachePath,
    );
    if (existingTask != null) {
      return FileAccessTransferRequest(
        task: existingTask,
        completion: waitForTransferTaskSuccess(
          existingTask.id,
        ).then((_) => cachePath),
      );
    }

    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: cachePath,
    );
    final completion = _runDownload(
      api: api,
      config: config,
      task: task,
      onSuccess: () async {
        await _cacheStore.upsertCacheRecord(
          bucket: bucket,
          object: remoteObject,
          localPath: cachePath,
        );
      },
      onFailure: () async {
        await _cacheStore.removeCacheRecord(
          bucket: bucket,
          objectKey: remoteObject.key,
          localPath: cachePath,
          deleteFile: true,
        );
      },
    ).then((_) => cachePath);
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<FileAccessTransferRequest?> prepareDownloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    if (object.isDir) {
      final targetDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: '下载到',
        initialDirectory: await resolveDefaultDownloadDirectory(
          config.defaultDownloadDirectory,
        ),
      );
      if (targetDirectory == null || targetDirectory.trim().isEmpty) {
        return null;
      }
      return prepareDownloadObjectToPath(
        api: api,
        config: config,
        bucket: bucket,
        object: object,
        savePath: uniqueDownloadDirectoryPath(
          targetDirectory,
          object.displayName,
        ),
      );
    }
    final initialDirectory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    final savePath = await FilePicker.saveFile(
      dialogTitle: '下载到',
      fileName: object.displayName,
      initialDirectory: initialDirectory,
    );
    if (savePath == null || savePath.trim().isEmpty) {
      return null;
    }

    return prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: savePath,
    );
  }

  Future<FileAccessTransferRequest> prepareDownloadObjectToDefaultDirectory({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final directory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    if (directory == null || directory.trim().isEmpty) {
      throw StateError('无法解析默认下载目录，请使用另存为选择保存位置。');
    }
    return prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.isDir
          ? uniqueDownloadDirectoryPath(directory, object.displayName)
          : uniqueDownloadPath(directory, object.displayName),
    );
  }

  Future<String> prepareLocalCopyPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    if (object.isDir) {
      throw UnsupportedError('暂不支持复制文件夹到系统剪贴板');
    }
    return _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  Future<void> downloadObjectToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    required String savePath,
  }) async {
    final request = await prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: savePath,
    );
    await request.completion;
  }

  Future<FileAccessTransferRequest> prepareDownloadObjectToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    required String savePath,
  }) async {
    if (savePath.trim().isEmpty) {
      return FileAccessTransferRequest(completion: Future.value(savePath));
    }
    if (object.isDir) {
      final task = TransferQueue.instance.startTask(
        kind: TransferKind.download,
        bucket: bucket,
        key: object.key,
        localPath: savePath,
      );
      final completion = _runDirectoryDownload(
        api: api,
        config: config,
        task: task,
        directory: object,
        savePath: savePath,
      ).then((_) => savePath);
      return FileAccessTransferRequest(task: task, completion: completion);
    }

    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: savePath,
    );
    final completion = runDownloadToPathWithCache(
      cacheStore: _cacheStore,
      config: config,
      task: task,
      object: object,
      savePath: savePath,
      remoteDownload: () => _runDownload(
        api: api,
        config: config,
        task: task,
        onFailure: () => deleteFileIfExists(savePath),
      ),
    ).then((_) => savePath);
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<void> evictCacheForObject({
    required RemoteStorageConfig config,
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
        throw StateError('下载已取消');
      }
      rethrow;
    }
  }

  Future<void> _runDirectoryDownload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required TransferTask task,
    required ObjectInfo directory,
    required String savePath,
  }) async {
    try {
      await _downloadDirectoryToPath(
        api: api,
        config: config,
        bucket: task.bucket,
        task: task,
        directory: directory,
        savePath: savePath,
      );
      TransferQueue.instance.markTaskDone(task.id);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      if (TransferQueue.instance.statusOf(task.id) == TransferStatus.canceled) {
        throw StateError('下载已取消');
      }
      rethrow;
    }
  }

  Future<void> _downloadDirectoryToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required TransferTask task,
    required ObjectInfo directory,
    required String savePath,
  }) async {
    final root = Directory(savePath);
    await root.create(recursive: true);
    final files = await _listFilesRecursively(
      api: api,
      config: config,
      bucket: bucket,
      prefix: directory.key,
    );
    for (final file in files) {
      if (TransferQueue.instance.statusOf(task.id) == TransferStatus.canceled) {
        throw StateError('下载已取消');
      }
      final relativeKey = path.posix.relative(file.key, from: directory.key);
      final localPath = path.joinAll([
        savePath,
        ...path.posix.split(relativeKey),
      ]);
      await Directory(path.dirname(localPath)).create(recursive: true);
      final copied = await copyCachedObjectToPath(
        cacheStore: _cacheStore,
        config: config,
        bucket: bucket,
        object: file,
        savePath: localPath,
      );
      if (copied) {
        continue;
      }
      await downloadObjectToPath(
        api: api,
        config: config,
        bucket: bucket,
        object: file,
        savePath: localPath,
      );
    }
  }

  Future<List<ObjectInfo>> _listFilesRecursively({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required String prefix,
  }) async {
    final items = await api.listObjects(config, bucket, prefix);
    final files = <ObjectInfo>[];
    for (final item in items) {
      if (item.key == prefix) {
        continue;
      }
      if (item.isDir) {
        files.addAll(
          await _listFilesRecursively(
            api: api,
            config: config,
            bucket: bucket,
            prefix: item.key,
          ),
        );
      } else {
        files.add(item);
      }
    }
    return files;
  }
}
