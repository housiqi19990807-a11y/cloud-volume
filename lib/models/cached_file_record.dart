// Cached file metadata mirrors the SQLite record used for local open/download reuse.

class CachedFileRecord {
  const CachedFileRecord({
    required this.bucket,
    required this.objectKey,
    required this.localPath,
    required this.fileSize,
    required this.lastModified,
    required this.updatedAtEpochMs,
  });

  factory CachedFileRecord.fromJson(Map<String, Object?> json) {
    return CachedFileRecord(
      bucket: (json['bucket'] ?? '').toString(),
      objectKey: (json['object_key'] ?? '').toString(),
      localPath: (json['local_path'] ?? '').toString(),
      fileSize: (json['file_size'] as int?) ?? 0,
      lastModified: (json['last_modified'] ?? '').toString(),
      updatedAtEpochMs: (json['updated_at_epoch_ms'] as int?) ?? 0,
    );
  }

  final String bucket;
  final String objectKey;
  final String localPath;
  final int fileSize;
  final String lastModified;
  final int updatedAtEpochMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bucket': bucket,
      'object_key': objectKey,
      'local_path': localPath,
      'file_size': fileSize,
      'last_modified': lastModified,
      'updated_at_epoch_ms': updatedAtEpochMs,
    };
  }
}
