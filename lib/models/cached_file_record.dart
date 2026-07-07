// Cached file metadata mirrors the Go bridge preview-cache index record.

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
      objectKey: (json['objectKey'] ?? json['object_key'] ?? '').toString(),
      localPath: (json['localPath'] ?? json['local_path'] ?? '').toString(),
      fileSize: _readInt(json['fileSize'] ?? json['file_size']),
      lastModified: (json['lastModified'] ?? json['last_modified'] ?? '')
          .toString(),
      updatedAtEpochMs: _readInt(
        json['updatedAtEpochMs'] ?? json['updated_at_epoch_ms'],
      ),
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
      'objectKey': objectKey,
      'localPath': localPath,
      'fileSize': fileSize,
      'lastModified': lastModified,
      'updatedAtEpochMs': updatedAtEpochMs,
    };
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
