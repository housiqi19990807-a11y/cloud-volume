// S3 bucket and object models for the file manager UI.

class BucketInfo {
  const BucketInfo({
    required this.name,
    this.quotaBytes = 0,
    this.usedBytes = 0,
  });

  factory BucketInfo.fromJson(Map<String, dynamic> json) {
    return BucketInfo(
      name: (json['name'] ?? '').toString(),
      quotaBytes: _nonNegativeBucketBytes(json['quotaBytes']),
      usedBytes: _nonNegativeBucketBytes(json['usedBytes']),
    );
  }

  final String name;
  final int quotaBytes;
  final int usedBytes;
}

int _nonNegativeBucketBytes(dynamic value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : 0;
}

class ObjectInfo {
  const ObjectInfo({
    required this.key,
    required this.size,
    this.lastModified = "",
    required this.isDir,
  });

  factory ObjectInfo.fromJson(Map<String, dynamic> json) {
    return ObjectInfo(
      key: (json['key'] ?? '').toString(),
      size: (json['size'] ?? 0) as int,
      lastModified: (json['lastModified'] ?? '').toString(),
      isDir: json['isDir'] == true,
    );
  }

  final String key;
  final int size;
  final String lastModified;
  final bool isDir;

  /// Display name: last path segment for objects, or trimmed prefix for dirs.
  String get displayName {
    if (isDir) {
      final trimmed = key.replaceAll(RegExp(r'/+$'), '');
      return trimmed.split('/').last;
    }
    return key.split('/').last;
  }

  /// Human-readable file size.
  String get sizeText {
    if (isDir) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class DirectoryAccess {
  const DirectoryAccess({
    required this.writable,
    required this.known,
    this.reason = '',
  });

  factory DirectoryAccess.fromJson(Map<String, dynamic> json) {
    return DirectoryAccess(
      writable: json['writable'] == true,
      known: json['known'] == true,
      reason: (json['reason'] ?? '').toString(),
    );
  }

  final bool writable;
  final bool known;
  final String reason;
}
