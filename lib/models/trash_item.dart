// Trash item model keeps app-level recycle bin metadata separate from object listings.
class TrashItem {
  const TrashItem({
    required this.id,
    required this.name,
    required this.originalKey,
    required this.trashKey,
    required this.deletedAt,
    required this.isDir,
    required this.size,
    required this.objectCount,
  });

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      originalKey: (json['originalKey'] ?? '').toString(),
      trashKey: (json['trashKey'] ?? '').toString(),
      deletedAt: (json['deletedAt'] ?? '').toString(),
      isDir: json['isDir'] == true,
      size: (json['size'] ?? 0) as int,
      objectCount: (json['objectCount'] ?? 0) as int,
    );
  }

  final String id;
  final String name;
  final String originalKey;
  final String trashKey;
  final String deletedAt;
  final bool isDir;
  final int size;
  final int objectCount;

  String get sizeText {
    if (isDir) {
      return '$objectCount 项';
    }
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
