// File cache store persists local cached-file metadata without native libraries.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/s3_objects.dart';

class FileCacheStore {
  FileCacheStore._();

  static final FileCacheStore instance = FileCacheStore._();

  static const _indexFileName = 'remote_storage_cache.json';
  static const _cacheDirName = 'files';

  File? _indexFile;
  Map<String, CachedFileRecord>? _records;
  Future<void> _writeQueue = Future<void>.value();
  Directory? _cacheRoot;
  String? _cacheRootPath;

  Future<String?> findUsableCachePath(
    String cacheDirectory,
    String bucket,
    ObjectInfo remoteObject,
  ) async {
    final root = await _cacheDirectory(cacheDirectory);
    final records = await _loadRecords();
    final record = records[_recordKey(bucket, remoteObject.key)];
    if (record == null) {
      return null;
    }
    final file = File(record.localPath);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : -1;
    if (!_isInsideRoot(root.path, record.localPath) ||
        !fileExists ||
        !_matchesRemoteObject(record, remoteObject) ||
        fileSize != remoteObject.size) {
      await removeCacheRecord(
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
    required String bucket,
    required ObjectInfo object,
    required String localPath,
  }) async {
    final records = await _loadRecords();
    records[_recordKey(bucket, object.key)] = CachedFileRecord(
      bucket: bucket,
      objectKey: object.key,
      localPath: localPath,
      fileSize: object.size,
      lastModified: object.lastModified,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistRecords();
  }

  Future<void> removeCacheRecord({
    required String bucket,
    required String objectKey,
    String? localPath,
    bool deleteFile = false,
  }) async {
    final records = await _loadRecords();
    records.remove(_recordKey(bucket, objectKey));
    await _persistRecords();
    if (deleteFile && localPath != null) {
      await _deleteFileIfExists(localPath);
    }
  }

  Future<void> removeCachePrefix({
    required String bucket,
    required String objectKeyPrefix,
    bool deleteFiles = false,
  }) async {
    final records = await _loadRecords();
    final removedPaths = <String>[];
    records.removeWhere((_, record) {
      final matches =
          record.bucket == bucket &&
          record.objectKey.startsWith(objectKeyPrefix);
      if (matches && record.localPath.isNotEmpty) {
        removedPaths.add(record.localPath);
      }
      return matches;
    });
    await _persistRecords();
    if (!deleteFiles) {
      return;
    }
    for (final localPath in removedPaths) {
      await _deleteFileIfExists(localPath);
    }
  }

  Future<void> deleteFileIfExists(String localPath) async {
    await _deleteFileIfExists(localPath);
  }

  Future<Map<String, CachedFileRecord>> _loadRecords() async {
    if (_records != null) {
      return _records!;
    }
    final supportDir = await getApplicationSupportDirectory();
    await supportDir.create(recursive: true);
    _indexFile = File(path.join(supportDir.path, _indexFileName));
    if (!await _indexFile!.exists()) {
      _records = <String, CachedFileRecord>{};
      return _records!;
    }

    final text = await _indexFile!.readAsString();
    if (text.trim().isEmpty) {
      _records = <String, CachedFileRecord>{};
      return _records!;
    }
    final decoded = jsonDecode(text);
    final records = <String, CachedFileRecord>{};
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          final json = Map<String, Object?>.from(item);
          final record = CachedFileRecord.fromJson(json);
          records[_recordKey(record.bucket, record.objectKey)] = record;
        }
      }
    }
    _records = records;
    return _records!;
  }

  Future<void> _persistRecords() {
    _writeQueue = _writeQueue.then((_) async {
      final records = _records;
      final indexFile = _indexFile;
      if (records == null || indexFile == null) {
        return;
      }
      final rows = records.values.map((record) => record.toJson()).toList()
        ..sort((a, b) {
          final left = '${a['bucket']}\u0000${a['object_key']}';
          final right = '${b['bucket']}\u0000${b['object_key']}';
          return left.compareTo(right);
        });
      final tempFile = File('${indexFile.path}.tmp');
      const encoder = JsonEncoder.withIndent('  ');
      await tempFile.writeAsString(encoder.convert(rows));
      if (await indexFile.exists()) {
        await indexFile.delete();
      }
      await tempFile.rename(indexFile.path);
    });
    return _writeQueue;
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

  String _recordKey(String bucket, String objectKey) =>
      '$bucket\u0000$objectKey';

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
