// 挂载状态模型：描述当前 bucket 是否已经挂到桌面以及本地 WebDAV 会话信息。

class BucketMountStatus {
  const BucketMountStatus({
    required this.mounted,
    required this.bucket,
    required this.mountPath,
    required this.serverUrl,
    required this.port,
    this.lastError,
  });

  factory BucketMountStatus.fromJson(Map<String, dynamic> json) {
    return BucketMountStatus(
      mounted: json['mounted'] == true,
      bucket: (json['bucket'] ?? '').toString(),
      mountPath: (json['mountPath'] ?? '').toString(),
      serverUrl: (json['serverUrl'] ?? '').toString(),
      port: (json['port'] ?? 0) as int,
      lastError: json['lastError']?.toString(),
    );
  }

  final bool mounted;
  final String bucket;
  final String mountPath;
  final String serverUrl;
  final int port;
  final String? lastError;

  bool get hasError => (lastError ?? '').trim().isNotEmpty;
}
