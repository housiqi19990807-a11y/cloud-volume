// Tests for the multi-account bucket aggregation: one unreachable upstream
// must not block or hide the buckets of healthy accounts.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/bucket_source_service.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

void main() {
  test(
    'loadEntriesWithFailures isolates a failing account and keeps healthy ones',
    () async {
      final api = _FakeBucketSourceApi(
        configs: {
          'good': _config('good', 'https://good.example'),
          'bad': _config('bad', 'https://bad.example'),
        },
        // 'bad' throws; 'good' returns one bucket.
        bucketForProfile: {'good': const [BucketInfo(name: 'good-bucket')]},
        failingProfiles: {'bad'},
      );

      final result = await BucketSourceService.instance.loadEntriesWithFailures(
        api,
        const [
          ProfileInfo(
            name: 'good',
            displayName: 'good',
            storageType: StorageType.s3,
            providerType: StorageProviderType.s3,
            endpoint: 'https://good.example',
            accessKeyId: 'ak',
            active: false,
          ),
          ProfileInfo(
            name: 'bad',
            displayName: 'bad',
            storageType: StorageType.s3,
            providerType: StorageProviderType.s3,
            endpoint: 'https://bad.example',
            accessKeyId: 'ak',
            active: false,
          ),
        ],
        fallbackConfig: _config('default', 'https://default.example'),
      );

      // The healthy account's bucket survives.
      expect(
        result.entries.map((FileManagerBucketEntry e) => e.bucket.name),
        contains('good-bucket'),
      );
      // The failing account is reported, not swallowed.
      expect(
        result.failures.map((BucketSourceLoadFailure f) => f.profileName),
        contains('bad'),
      );
    },
  );

  test('loadEntriesWithFailures times out a stalled account instead of hanging',
      () async {
    // listBuckets never completes for 'slow'; the per-account timeout must
    // turn it into a failure rather than hanging the whole load forever.
    final api = _FakeBucketSourceApi(
      configs: {
        'fast': _config('fast', 'https://fast.example'),
        'slow': _config('slow', 'https://slow.example'),
      },
      bucketForProfile: {'fast': const [BucketInfo(name: 'fast-bucket')]},
      // 'slow' is in failingProfiles AND stalls — combine via stalledProfiles.
      stalledProfiles: {'slow'},
    );

    final result = await BucketSourceService.instance.loadEntriesWithFailures(
      api,
        const [
          ProfileInfo(
            name: 'fast',
            displayName: 'fast',
            storageType: StorageType.s3,
            providerType: StorageProviderType.s3,
            endpoint: 'https://fast.example',
            accessKeyId: 'ak',
            active: false,
          ),
          ProfileInfo(
            name: 'slow',
            displayName: 'slow',
            storageType: StorageType.s3,
            providerType: StorageProviderType.s3,
            endpoint: 'https://slow.example',
            accessKeyId: 'ak',
            active: false,
          ),
        ],
      fallbackConfig: _config('default', 'https://default.example'),
    );

    expect(
      result.entries.map((FileManagerBucketEntry e) => e.bucket.name),
      contains('fast-bucket'),
    );
    expect(
      result.failures.map((BucketSourceLoadFailure f) => f.profileName),
      contains('slow'),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}

RemoteStorageConfig _config(String display, String endpoint) {
  return RemoteStorageConfig.empty().copyWith(
    endpoint: endpoint,
    storageType: StorageType.s3,
    displayName: display,
    accessKeyId: 'ak',
  );
}

/// Minimal gateway fake: only loadProfile / listBuckets / listBucketOrder are
/// exercised by BucketSourceService, so the rest delegate to Fake (which
/// throws if accidentally called, surfacing misuse in tests).
class _FakeBucketSourceApi extends Fake implements RemoteStorageGateway {
  _FakeBucketSourceApi({
    required this.configs,
    required this.bucketForProfile,
    this.failingProfiles = const <String>{},
    this.stalledProfiles = const <String>{},
  });

  final Map<String, RemoteStorageConfig> configs;
  final Map<String, List<BucketInfo>> bucketForProfile;
  final Set<String> failingProfiles;
  final Set<String> stalledProfiles;

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async {
    if (!configs.containsKey(name)) {
      throw StateError('no config for profile $name');
    }
    return configs[name]!;
  }

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async {
    // Match by display name, which is unique per test config.
    final name = config.displayName;
    if (stalledProfiles.contains(name)) {
      // Never completes; the per-account timeout must rescue the aggregate.
      return Completer<List<BucketInfo>>().future;
    }
    if (failingProfiles.contains(name)) {
      throw StateError('upstream unreachable for $name');
    }
    return bucketForProfile[name] ?? const <BucketInfo>[];
  }

  @override
  Future<List<String>> listBucketOrder() async => const <String>[];
}
