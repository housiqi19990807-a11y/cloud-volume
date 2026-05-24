// File cache store persists local cached-file metadata and cache paths in SQLite.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FileCacheStore {
  FileCacheStore._();

  static final FileCacheStore instance = FileCacheStore._();

  static const _dbName = 'remote_storage_cache.db';
  static const _tableName = 'cached_files';
  static const _cacheDirName = 'file_cache';

  Database? _database;
  Directory? _cacheRoot;

  Future<String?> findUsableCachePath(String bucket, ObjectInfo object) async {
    final db = await _openDatabase();
    final rows = await db.query(
      _tableName,
      where: 'bucket = ? AND object_key = ?',
      whereArgs: <Object?>[bucket, object.key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final record = CachedFileRecord.fromJson(rows.first);
    final file = File(record.localPath);
    if (!await file.exists() || !_matchesObject(record, object)) {
      await removeCacheRecord(bucket: bucket, objectKey: object.key);
      return null;
    }
    return record.localPath;
  }

  Future<String> cachePathFor(String bucket, String objectKey) async {
    final root = await _cacheDirectory();
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
    final db = await _openDatabase();
    await db.insert(
      _tableName,
      CachedFileRecord(
        bucket: bucket,
        objectKey: object.key,
        localPath: localPath,
        fileSize: object.size,
        lastModified: object.lastModified,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeCacheRecord({
    required String bucket,
    required String objectKey,
    String? localPath,
    bool deleteFile = false,
  }) async {
    final db = await _openDatabase();
    await db.delete(
      _tableName,
      where: 'bucket = ? AND object_key = ?',
      whereArgs: <Object?>[bucket, objectKey],
    );
    if (deleteFile && localPath != null) {
      await _deleteFileIfExists(localPath);
    }
  }

  Future<void> removeCachePrefix({
    required String bucket,
    required String objectKeyPrefix,
    bool deleteFiles = false,
  }) async {
    final db = await _openDatabase();
    final rows = await db.query(
      _tableName,
      columns: const <String>['local_path'],
      where: 'bucket = ? AND object_key LIKE ?',
      whereArgs: <Object?>[bucket, '$objectKeyPrefix%'],
    );
    await db.delete(
      _tableName,
      where: 'bucket = ? AND object_key LIKE ?',
      whereArgs: <Object?>[bucket, '$objectKeyPrefix%'],
    );
    if (!deleteFiles) {
      return;
    }
    for (final row in rows) {
      final localPath = (row['local_path'] ?? '').toString();
      if (localPath.isNotEmpty) {
        await _deleteFileIfExists(localPath);
      }
    }
  }

  Future<void> deleteFileIfExists(String localPath) async {
    await _deleteFileIfExists(localPath);
  }

  Future<Database> _openDatabase() async {
    if (_database != null) {
      return _database!;
    }
    final supportDir = await getApplicationSupportDirectory();
    await supportDir.create(recursive: true);
    final dbPath = path.join(supportDir.path, _dbName);
    _database = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              bucket TEXT NOT NULL,
              object_key TEXT NOT NULL,
              local_path TEXT NOT NULL,
              file_size INTEGER NOT NULL,
              last_modified TEXT NOT NULL,
              updated_at_epoch_ms INTEGER NOT NULL,
              PRIMARY KEY (bucket, object_key)
            )
          ''');
        },
      ),
    );
    return _database!;
  }

  Future<Directory> _cacheDirectory() async {
    if (_cacheRoot != null) {
      return _cacheRoot!;
    }
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(path.join(supportDir.path, _cacheDirName));
    await cacheDir.create(recursive: true);
    _cacheRoot = cacheDir;
    return cacheDir;
  }

  bool _matchesObject(CachedFileRecord record, ObjectInfo object) {
    final sameSize = record.fileSize == object.size;
    final sameTimestamp =
        object.lastModified.isEmpty ||
        record.lastModified == object.lastModified;
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
}
