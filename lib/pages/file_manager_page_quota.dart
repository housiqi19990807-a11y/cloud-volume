// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

const Duration _bucketQuotaCacheTtl = Duration(minutes: 5);

// Remote quota refresh is deliberately second-stage so bucket discovery stays responsive.
extension _FileManagerPageQuota on _FileManagerPageState {
  List<FileManagerBucketEntry> _applyCachedBucketQuotas(
    List<FileManagerBucketEntry> entries,
  ) {
    return entries
        .map((entry) {
          final cached = _matchingQuotaCache(entry);
          return cached == null ? entry : entry.withBucketInfo(cached.bucket);
        })
        .toList(growable: false);
  }

  void _scheduleBucketQuotaRefresh(
    List<FileManagerBucketEntry> entries,
    int generation,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _bucketQuotaRefreshGeneration) return;
      unawaited(_refreshBucketQuotas(entries, generation));
    });
  }

  Future<void> _refreshBucketQuotas(
    List<FileManagerBucketEntry> entries,
    int generation,
  ) async {
    final now = DateTime.now();
    final candidates = entries
        .where((entry) => !_hasFreshQuotaCache(entry, now))
        .toList(growable: false);
    if (candidates.isEmpty) return;

    final results = await Future.wait<MapEntry<String, BucketInfo>?>(
      candidates.map((entry) async {
        try {
          final quota = await widget.api.getBucketQuota(
            entry.config,
            entry.bucket.name,
          );
          _bucketQuotaCache[entry.id] = _BucketQuotaCacheValue(
            bucket: quota,
            configSignature: _quotaConfigSignature(entry),
            fetchedAt: DateTime.now(),
          );
          return MapEntry(entry.id, quota);
        } catch (error) {
          // Bridge setup failures happen before Go can log, so record them here.
          unawaited(
            AppLog.error(
              'quota refresh failed profile=${entry.profileName} '
              'bucket=${entry.bucket.name} error=$error',
              tag: 'quota',
            ),
          );
          return null;
        }
      }),
    );
    if (!mounted || generation != _bucketQuotaRefreshGeneration) return;

    final updates = Map<String, BucketInfo>.fromEntries(
      results.whereType<MapEntry<String, BucketInfo>>(),
    );
    if (updates.isEmpty) return;

    final current = _buckets;
    if (current == null) return;
    setState(() {
      _buckets = current
          .map(
            (entry) => updates[entry.id] == null
                ? entry
                : entry.withBucketInfo(updates[entry.id]!),
          )
          .toList(growable: false);
    });
  }

  _BucketQuotaCacheValue? _matchingQuotaCache(FileManagerBucketEntry entry) {
    final cached = _bucketQuotaCache[entry.id];
    if (cached == null) return null;
    if (cached.configSignature == _quotaConfigSignature(entry)) return cached;
    _bucketQuotaCache.remove(entry.id);
    return null;
  }

  bool _hasFreshQuotaCache(FileManagerBucketEntry entry, DateTime now) {
    final cached = _matchingQuotaCache(entry);
    return cached != null &&
        now.difference(cached.fetchedAt) < _bucketQuotaCacheTtl;
  }

  int _quotaConfigSignature(FileManagerBucketEntry entry) {
    final config = entry.config;
    return Object.hashAll(<Object?>[
      config.storageType,
      config.endpoint,
      config.accessKeyId,
      config.secretAccessKey,
      config.webdavUsername,
      config.webdavPassword,
      config.rootPrefix,
    ]);
  }
}

class _BucketQuotaCacheValue {
  const _BucketQuotaCacheValue({
    required this.bucket,
    required this.configSignature,
    required this.fetchedAt,
  });

  final BucketInfo bucket;
  final int configSignature;
  final DateTime fetchedAt;
}
