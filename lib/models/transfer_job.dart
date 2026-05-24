// 传输快照模型：承接 Go bridge 返回的实时上传/下载状态。

class TransferSnapshot {
  const TransferSnapshot({
    required this.id,
    required this.type,
    required this.bucket,
    required this.key,
    required this.localPath,
    required this.status,
    required this.bytesCompleted,
    required this.totalBytes,
    required this.speedBytes,
    this.error,
  });

  factory TransferSnapshot.fromJson(Map<String, dynamic> json) {
    return TransferSnapshot(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      bytesCompleted: (json['bytesCompleted'] ?? 0) as int,
      totalBytes: (json['totalBytes'] ?? 0) as int,
      speedBytes: (json['speedBytes'] ?? 0).toDouble(),
      error: json['error']?.toString(),
    );
  }

  final String id;
  final String type;
  final String bucket;
  final String key;
  final String localPath;
  final String status;
  final int bytesCompleted;
  final int totalBytes;
  final double speedBytes;
  final String? error;
}
