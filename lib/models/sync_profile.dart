import 'package:remote_storage/models/sync_remote_open_request.dart';
// Sync profile model mirroring go/sync/profile.go for the Flutter settings UI.
// Keeps field names in sync with the JSON bridge payload.

/// 同步方向：仅上传 / 仅下载 / 双向。
enum SyncDirection {
  upload('upload', '仅上传（本地 → 远端）'),
  download('download', '仅下载（远端 → 本地）'),
  twoway('twoway', '双向同步');

  const SyncDirection(this.value, this.label);
  final String value;
  final String label;

  static SyncDirection fromValue(String value) {
    return SyncDirection.values.firstWhere(
      (d) => d.value == value,
      orElse: () => SyncDirection.twoway,
    );
  }
}

/// 冲突策略：当本地与远端同时变更时如何处理。
enum SyncConflictPolicy {
  newest('newest', '保留较新版本'),
  localWins('local_wins', '保留本地版本'),
  remoteWins('remote_wins', '保留远端版本'),
  skip('skip', '跳过冲突文件');

  const SyncConflictPolicy(this.value, this.label);
  final String value;
  final String label;

  static SyncConflictPolicy fromValue(String value) {
    return SyncConflictPolicy.values.firstWhere(
      (p) => p.value == value,
      orElse: () => SyncConflictPolicy.newest,
    );
  }
}

/// 同步配置运行时状态。
enum SyncProfileStatus {
  idle('idle', '空闲'),
  syncing('syncing', '同步中'),
  error('error', '错误'),
  paused('paused', '已暂停');

  const SyncProfileStatus(this.value, this.label);
  final String value;
  final String label;

  static SyncProfileStatus fromValue(String value) {
    return SyncProfileStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => SyncProfileStatus.idle,
    );
  }
}

/// 一条文件同步配置（本地目录 ↔ 远端桶目录）。
class SyncProfile {
  SyncProfile({
    required this.id,
    required this.name,
    required this.accountProfile,
    required this.bucket,
    required this.remotePrefix,
    required this.localPath,
    required this.direction,
    required this.intervalSeconds,
    required this.conflictPolicy,
    required this.excludePatterns,
    required this.quietSeconds,
    required this.enabled,
  });

  factory SyncProfile.fromJson(Map<String, dynamic> json) {
    return SyncProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      accountProfile: (json['accountProfile'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      remotePrefix: (json['remotePrefix'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      direction: SyncDirection.fromValue((json['direction'] ?? '').toString()),
      intervalSeconds: (json['intervalSeconds'] ?? 300) as int,
      conflictPolicy:
          SyncConflictPolicy.fromValue((json['conflictPolicy'] ?? '').toString()),
      excludePatterns:
          (json['excludePatterns'] as List<dynamic>? ?? <dynamic>[])
              .map((e) => e.toString())
              .toList(),
      quietSeconds: (json['quietSeconds'] ?? 10) as int,
      enabled: json['enabled'] == true,
    );
  }

  final String id;
  final String name;
  final String accountProfile;
  final String bucket;
  final String remotePrefix;
  final String localPath;
  final SyncDirection direction;
  final int intervalSeconds;
  final SyncConflictPolicy conflictPolicy;
  final List<String> excludePatterns;
  final int quietSeconds;
  final bool enabled;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'accountProfile': accountProfile,
      'bucket': bucket,
      'remotePrefix': remotePrefix,
      'localPath': localPath,
      'direction': direction.value,
      'intervalSeconds': intervalSeconds,
      'conflictPolicy': conflictPolicy.value,
      'excludePatterns': excludePatterns,
      'quietSeconds': quietSeconds,
      'enabled': enabled,
    };
  }

  SyncProfile copyWith({
    String? id,
    String? name,
    String? accountProfile,
    String? bucket,
    String? remotePrefix,
    String? localPath,
    SyncDirection? direction,
    int? intervalSeconds,
    SyncConflictPolicy? conflictPolicy,
    List<String>? excludePatterns,
    int? quietSeconds,
    bool? enabled,
  }) {
    return SyncProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      accountProfile: accountProfile ?? this.accountProfile,
      bucket: bucket ?? this.bucket,
      remotePrefix: remotePrefix ?? this.remotePrefix,
      localPath: localPath ?? this.localPath,
      direction: direction ?? this.direction,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      quietSeconds: quietSeconds ?? this.quietSeconds,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// 带运行时状态的同步配置视图，供 UI 展示当前进度。
class SyncProfileRuntime {
  SyncProfileRuntime({
    required this.profile,
    required this.status,
    required this.lastSyncAt,
    required this.lastError,
    required this.pendingOps,
    required this.lastOpsCount,
  });

  factory SyncProfileRuntime.fromJson(Map<String, dynamic> json) {
    return SyncProfileRuntime(
      profile: SyncProfile.fromJson(json),
      status: SyncProfileStatus.fromValue((json['status'] ?? '').toString()),
      lastSyncAt: (json['lastSyncAt'] ?? '').toString(),
      lastError: (json['lastError'] ?? '').toString(),
      pendingOps: (json['pendingOps'] ?? 0) as int,
      lastOpsCount: (json['lastOpsCount'] ?? 0) as int,
    );
  }

  final SyncProfile profile;
  final SyncProfileStatus status;
  final String lastSyncAt;
  final String lastError;
  final int pendingOps;
  final int lastOpsCount;
}


extension SyncProfileRemoteOpen on SyncProfile {
  SyncRemoteOpenRequest get remoteOpenRequest => SyncRemoteOpenRequest(
        profileName: accountProfile,
        bucket: bucket,
        remotePrefix: remotePrefix,
      );
}
