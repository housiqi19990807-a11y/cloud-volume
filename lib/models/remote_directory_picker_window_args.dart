// Args for the remote-directory picker sub-window (JSON over multi-window boundary).

import 'dart:convert';

import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';

class RemoteDirectoryPickerWindowArgs {
  const RemoteDirectoryPickerWindowArgs({
    required this.requestId,
    required this.creatorWindowId,
    required this.buckets,
    this.initialBucket,
    this.initialPrefix,
    this.initialProfileName,
  });

  static const String businessId = 'remote_directory_picker';

  final String requestId;
  final String creatorWindowId;
  final List<FileManagerBucketEntry> buckets;
  final String? initialBucket;
  final String? initialPrefix;
  final String? initialProfileName;

  factory RemoteDirectoryPickerWindowArgs.fromArguments(String arguments) {
    final json = jsonDecode(arguments) as Map<String, dynamic>;
    final bucketMaps = json['buckets'] as List<dynamic>? ?? [];
    return RemoteDirectoryPickerWindowArgs(
      requestId: json['requestId'] as String? ?? '',
      creatorWindowId: json['creatorWindowId'] as String? ?? '',
      buckets: bucketMaps
          .map((e) => _bucketEntryFromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      initialBucket: json['initialBucket'] as String?,
      initialPrefix: json['initialPrefix'] as String?,
      initialProfileName: json['initialProfileName'] as String?,
    );
  }

  String toArguments() {
    return jsonEncode(<String, dynamic>{
      'businessId': businessId,
      'requestId': requestId,
      'creatorWindowId': creatorWindowId,
      'buckets': buckets.map(_bucketEntryToJson).toList(),
      if (initialBucket != null) 'initialBucket': initialBucket,
      if (initialPrefix != null) 'initialPrefix': initialPrefix,
      if (initialProfileName != null) 'initialProfileName': initialProfileName,
    });
  }

  static bool matches(String arguments) {
    if (arguments.trim().isEmpty) return false;
    try {
      final json = jsonDecode(arguments) as Map<String, dynamic>;
      return json['businessId'] == businessId;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _bucketEntryToJson(FileManagerBucketEntry e) {
    return {
      'id': e.id,
      'profileName': e.profileName,
      'sourceLabel': e.sourceLabel,
      'bucketName': e.bucket.name,
      'config': e.config.toJson(),
    };
  }

  static FileManagerBucketEntry _bucketEntryFromJson(Map<String, dynamic> json) {
    final bucketMap = Map<String, dynamic>.from(json['bucket'] as Map? ?? {});
    if (bucketMap.isEmpty && json['bucketName'] != null) {
      bucketMap['name'] = json['bucketName'];
    }
    return FileManagerBucketEntry(
      id: json['id'] as String? ?? '',
      bucket: BucketInfo.fromJson(bucketMap),
      profileName: json['profileName'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      config: RemoteStorageConfig.fromJson(
        Map<String, dynamic>.from(json['config'] as Map? ?? {}),
      ),
    );
  }
}
