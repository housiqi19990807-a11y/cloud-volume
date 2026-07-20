// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// Remote quota refresh is deliberately second-stage so bucket discovery stays responsive.
extension _FileManagerPageQuota on _FileManagerPageState {
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
    final results = await Future.wait<MapEntry<String, BucketInfo>?>(
      entries.map((entry) async {
        try {
          final quota = await widget.api.getBucketQuota(
            entry.config,
            entry.bucket.name,
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
}
