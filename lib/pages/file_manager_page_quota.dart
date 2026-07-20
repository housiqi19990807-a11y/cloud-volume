// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// Remote quota refresh is deliberately second-stage so bucket discovery stays responsive.
extension _FileManagerPageQuota on _FileManagerPageState {
  Future<void> _refreshBucketQuotas(
    List<FileManagerBucketEntry> entries,
    int generation,
  ) async {
    final api = widget.api;
    if (api is! BucketQuotaQuery) return;
    final quotaApi = api as BucketQuotaQuery;

    final candidates = entries
        .where(
          (entry) =>
              entry.config.storageType == StorageType.baiduPan ||
              entry.config.storageType == StorageType.webdav,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return;

    final results = await Future.wait<MapEntry<String, BucketInfo>?>(
      candidates.map((entry) async {
        try {
          final quota = await quotaApi.getBucketQuota(
            entry.config,
            entry.bucket.name,
          );
          return MapEntry(entry.id, quota);
        } catch (_) {
          // The Go backend records the error; capacity is optional in the UI.
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
