// File manager bucket entries keep the originating account attached to each bucket row.

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';

class FileManagerBucketEntry {
  const FileManagerBucketEntry({
    required this.id,
    required this.bucket,
    required this.profileName,
    required this.sourceLabel,
    required this.config,
    this.displayName = '',
    this.rootPrefix = '',
  });

  factory FileManagerBucketEntry.fromBucketInfo({
    required BucketInfo bucket,
    required String profileName,
    required String sourceLabel,
    required RemoteStorageConfig config,
    BucketViewSettings? view,
  }) {
    final configuredPrefix = view?.rootPrefix.trim() ?? '';
    final accountPrefix = config.rootPrefix.trim();
    final effectivePrefix = <String>[
      accountPrefix,
      configuredPrefix,
    ].where((part) => part.isNotEmpty).join('/');
    return FileManagerBucketEntry(
      id: '$profileName::${bucket.name}',
      bucket: bucket,
      profileName: profileName,
      sourceLabel: sourceLabel,
      config: config.copyWith(rootPrefix: effectivePrefix),
      displayName: view?.displayName.trim() ?? '',
      rootPrefix: configuredPrefix,
    );
  }

  final String id;
  final BucketInfo bucket;
  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
  final String displayName;
  final String rootPrefix;

  String get label => displayName.isEmpty ? bucket.name : displayName;

  FileManagerBucketEntry withBucketInfo(BucketInfo value) {
    return FileManagerBucketEntry(
      id: id,
      bucket: value,
      profileName: profileName,
      sourceLabel: sourceLabel,
      config: config,
      displayName: displayName,
      rootPrefix: rootPrefix,
    );
  }
}
