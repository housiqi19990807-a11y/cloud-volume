// 文件管理位置模型：统一表示桶列表、桶根目录和子目录，供导航历史复用。

class FileManagerLocation {
  const FileManagerLocation({required this.bucket, this.prefix = ''});

  final String? bucket;
  final String prefix;

  bool get isBucketList => bucket == null;

  @override
  bool operator ==(Object other) {
    return other is FileManagerLocation &&
        other.bucket == bucket &&
        other.prefix == prefix;
  }

  @override
  int get hashCode => Object.hash(bucket, prefix);
}
