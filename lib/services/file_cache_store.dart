// File cache store validates cached files while Go bridge persists the index.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/utils/app_log.dart';

class FileCacheStore {
  FileCacheStore._();

  static final FileCacheStore instance = FileCacheStore._();

  static const _cacheDirName = 'files';

  Directory? _cacheRoot;
  String? _cacheRootPath;

  Future<String?> findUsableCachePath(
    RemoteStorageGateway api,
    String cacheDirectory,
    String bucket,
    ObjectInfo remoteObject,
  ) async {
    final root = await _cacheDirectory(cacheDirectory);
    final indexWatch = Stopwatch()..start();
    final record = await api.findCacheIndexRecord(
      bucket: bucket,
      objectKey: remoteObject.key,
    );
    unawaited(
      AppLog.info(
        'cache index find bucket=$bucket key=${remoteObject.key} phaseMs=${indexWatch.elapsedMilliseconds} hit=${record != null}',
        tag: 'preview',
      ),
    );
    if (record == null) {
      return null;
    }
    final validateWatch = Stopwatch()..start();
    final file = File(record.localPath);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : -1;
    final insideRoot = _isInsideRoot(root.path, record.localPath);
    final matchesRemote = _matchesRemoteObject(record, remoteObject);
    final valid =
        insideRoot &&
        fileExists &&
        matchesRemote &&
        fileSize == remoteObject.size;
    unawaited(
      AppLog.info(
        'cache validate bucket=$bucket key=${remoteObject.key} phaseMs=${validateWatch.elapsedMilliseconds} valid=$valid insideRoot=$insideRoot exists=$fileExists fileSize=$fileSize remoteSize=${remoteObject.size} matchesRemote=$matchesRemote',
        tag: 'preview',
      ),
    );
    if (!valid) {
      await removeCacheRecord(
        api: api,
        bucket: bucket,
        objectKey: remoteObject.key,
        localPath: record.localPath,
        deleteFile: true,
      );
      return null;
    }
    return record.localPath;
  }

  Future<String> cachePathFor(
    String cacheDirectory,
    String bucket,
    String objectKey,
  ) async {
    final root = await _cacheDirectory(cacheDirectory);
    final segments = <String>[
      root.path,
      _safeSegment(bucket),
      ...objectKey
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .map(_safeSegment),
    ];
    final fullPath = path.joinAll(segments);
    await Directory(path.dirname(fullPath)).create(recursive: true);
    return fullPath;
  }

  Future<void> upsertCacheRecord({
    required RemoteStorageGateway api,
    required String bucket,
    required ObjectInfo object,
    required String localPath,
  }) async {
    await api.upsertCacheIndexRecord(
      CachedFileRecord(
        bucket: bucket,
        objectKey: object.key,
        localPath: localPath,
        fileSize: object.size,
        lastModified: object.lastModified,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> removeCacheRecord({
    required RemoteStorageGateway api,
    required String bucket,
    required String objectKey,
    String? localPath,
    bool deleteFile = false,
  }) async {
    await api.removeCacheIndexRecord(bucket: bucket, objectKey: objectKey);
    if (deleteFile && localPath != null) {
      await _deleteFileIfExists(localPath);
    }
  }

  Future<void> removeCachePrefix({
    required RemoteStorageGateway api,
    required String bucket,
    required String objectKeyPrefix,
    bool deleteFiles = false,
  }) async {
    final removed = await api.removeCacheIndexPrefix(
      bucket: bucket,
      objectKeyPrefix: objectKeyPrefix,
    );
    if (!deleteFiles) {
      return;
    }
    for (final record in removed) {
      if (record.localPath.isNotEmpty) {
        await _deleteFileIfExists(record.localPath);
      }
    }
  }

  Future<void> deleteFileIfExists(String localPath) async {
    await _deleteFileIfExists(localPath);
  }

  Future<Directory> _cacheDirectory(String cacheDirectory) async {
    final trimmedPath = cacheDirectory.trim();
    if (trimmedPath.isEmpty) {
      throw StateError('缓存目录未配置。');
    }
    final targetPath = path.join(trimmedPath, _cacheDirName);
    if (_cacheRoot != null && _cacheRootPath == targetPath) {
      return _cacheRoot!;
    }
    final cacheDir = Directory(targetPath);
    await cacheDir.create(recursive: true);
    _cacheRoot = cacheDir;
    _cacheRootPath = targetPath;
    return cacheDir;
  }

  bool _matchesRemoteObject(CachedFileRecord record, ObjectInfo remoteObject) {
    final sameSize = record.fileSize == remoteObject.size;
    final sameTimestamp =
        remoteObject.lastModified.isEmpty ||
        record.lastModified == remoteObject.lastModified;
    return sameSize && sameTimestamp;
  }

  String _safeSegment(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '_';
    }
    return trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '__');
  }

  Future<void> _deleteFileIfExists(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  bool _isInsideRoot(String rootPath, String localPath) {
    final normalizedRoot = path.normalize(rootPath);
    final normalizedLocal = path.normalize(localPath);
    return path.equals(normalizedRoot, normalizedLocal) ||
        path.isWithin(normalizedRoot, normalizedLocal);
  }
}
