// File access service owns click-to-open, explicit download, and cache bookkeeping.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_cache_store.dart';
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

  Future<String> _ensureCachedObject({
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
      return cachedPath;
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
      throw StateError('文件正在下载，完成后再预览。');
    }

    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
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
    );
    return cachePath;
  }

  Future<void> downloadObjectWithPicker({
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
        return;
      }
      await downloadObjectToPath(
        api: api,
        config: config,
        bucket: bucket,
        object: object,
        savePath: _uniqueDownloadDirectoryPath(
          targetDirectory,
          object.displayName,
        ),
      );
      return;
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
      return;
    }

    await downloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: savePath,
    );
  }

  Future<void> downloadObjectToDefaultDirectory({
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
    await downloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.isDir
          ? _uniqueDownloadDirectoryPath(directory, object.displayName)
          : _uniqueDownloadPath(directory, object.displayName),
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
    if (savePath.trim().isEmpty) {
      return;
    }
    if (object.isDir) {
      await _downloadDirectoryToPath(
        api: api,
        config: config,
        bucket: bucket,
        directory: object,
        savePath: savePath,
      );
      return;
    }

    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
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
        return;
      }
      rethrow;
    }
  }

  Future<void> _downloadDirectoryToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
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
      final relativeKey = path.posix.relative(file.key, from: directory.key);
      final localPath = path.joinAll([
        savePath,
        ...path.posix.split(relativeKey),
      ]);
      await Directory(path.dirname(localPath)).create(recursive: true);
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

  Future<void> _deleteFileIfExists(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _uniqueDownloadPath(String directory, String fileName) {
    var candidate = path.join(directory, fileName);
    if (!File(candidate).existsSync()) {
      return candidate;
    }
    final extension = path.extension(fileName);
    final baseName = path.basenameWithoutExtension(fileName);
    for (var index = 1; index < 1000; index += 1) {
      candidate = path.join(directory, '$baseName ($index)$extension');
      if (!File(candidate).existsSync()) {
        return candidate;
      }
    }
    return path.join(
      directory,
      '$baseName-${DateTime.now().millisecondsSinceEpoch}$extension',
    );
  }

  String _uniqueDownloadDirectoryPath(String directory, String name) {
    var candidate = path.join(directory, name);
    if (!Directory(candidate).existsSync() && !File(candidate).existsSync()) {
      return candidate;
    }
    for (var index = 1; index < 1000; index += 1) {
      candidate = path.join(directory, '$name ($index)');
      if (!Directory(candidate).existsSync() && !File(candidate).existsSync()) {
        return candidate;
      }
    }
    return path.join(
      directory,
      '$name-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
