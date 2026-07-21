// Bucket source aggregation.
//
// Centralizes the "list buckets for every account, apply per-account
// bucket-visibility allowlist, respect saved bucket order" pipeline that the
// file-manager home view, the global trash page, and other surfaces need.
// Before this service existed, file_manager_page_sources.dart owned the only
// copy and the global trash page re-implemented a single-account subset,
// which is why the trash page could not see buckets from other accounts.
//
// The service is stateless: every call re-reads profiles from the gateway so
// freshly added / deleted accounts are picked up immediately. Callers that
// need caching (the file manager's quota cache) layer that on top.

import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

/// A single account's resolved config plus the labels the UI shows alongside
/// its buckets. Mirrors the old private `_BucketSourceConfig`.
class BucketSource {
  const BucketSource({
    required this.profileName,
    required this.sourceLabel,
    required this.config,
  });

  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
}

/// Thrown when a single account fails to load or list buckets. Carries the
/// profile name so callers can offer "edit this account's credentials".
class BucketSourceLoadException implements Exception {
  const BucketSourceLoadException(this.profileName, this.cause);

  final String profileName;
  final Object cause;

  @override
  String toString() => cause.toString();
}

/// Aggregates buckets across all configured accounts.
class BucketSourceService {
  BucketSourceService._();

  static final BucketSourceService instance = BucketSourceService._();

  /// Resolves the [RemoteStorageConfig] for every profile in [profiles].
  ///
  /// When [profiles] is empty the active [fallbackConfig] is used as the only
  /// source, matching the pre-existing file-manager behaviour.
  Future<List<BucketSource>> loadSources(
    RemoteStorageGateway api,
    List<ProfileInfo> profiles, {
    required RemoteStorageConfig fallbackConfig,
  }) async {
    if (profiles.isEmpty) {
      return <BucketSource>[
        BucketSource(
          profileName: 'default',
          sourceLabel: _sourceLabelForConfig(fallbackConfig),
          config: fallbackConfig,
        ),
      ];
    }
    return Future.wait(
      profiles.map((profile) async {
        try {
          final config = await api.loadProfile(profile.name);
          return BucketSource(
            profileName: profile.name,
            sourceLabel: _sourceLabelForConfig(config),
            config: config,
          );
        } catch (error, stackTrace) {
          Error.throwWithStackTrace(
            BucketSourceLoadException(profile.name, error),
            stackTrace,
          );
        }
      }),
    );
  }

  /// Lists buckets for every source, applies per-account bucket-visibility
  /// allowlist, and returns ordered [FileManagerBucketEntry]s.
  ///
  /// The returned order follows the saved bucket order when present
  /// (`api.listBucketOrder`); otherwise accounts appear in profile order and
  /// buckets within an account are sorted by label.
  Future<List<FileManagerBucketEntry>> loadEntries(
    RemoteStorageGateway api,
    List<ProfileInfo> profiles, {
    required RemoteStorageConfig fallbackConfig,
  }) async {
    final sources = await loadSources(
      api,
      profiles,
      fallbackConfig: fallbackConfig,
    );
    final entries = <FileManagerBucketEntry>[];
    for (final source in sources) {
      final List<BucketInfo> buckets;
      try {
        buckets = await api.listBuckets(source.config);
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          BucketSourceLoadException(source.profileName, error),
          stackTrace,
        );
      }
      final views = source.config.bucketViews;
      for (final bucket in buckets) {
        final view = views[bucket.name];
        // Non-empty bucketViews acts as an allowlist: buckets without an entry
        // are hidden. An empty map means "show everything dynamically".
        if (views.isNotEmpty && view == null) continue;
        entries.add(
          FileManagerBucketEntry.fromBucketInfo(
            bucket: bucket,
            profileName: source.profileName,
            sourceLabel: source.sourceLabel,
            config: source.config,
            view: view,
          ),
        );
      }
    }

    final order = await api.listBucketOrder();
    if (order.isNotEmpty) {
      return _applySavedOrder(entries, order);
    }
    entries.sort((left, right) {
      final leftSource = sources.indexWhere(
        (source) => source.profileName == left.profileName,
      );
      final rightSource = sources.indexWhere(
        (source) => source.profileName == right.profileName,
      );
      if (leftSource != rightSource) {
        return leftSource.compareTo(rightSource);
      }
      return left.label.compareTo(right.label);
    });
    return entries;
  }

  List<FileManagerBucketEntry> _applySavedOrder(
    List<FileManagerBucketEntry> entries,
    List<String> order,
  ) {
    final byId = {for (final entry in entries) entry.id: entry};
    final ordered = <FileManagerBucketEntry>[];
    final seen = <String>{};
    for (final id in order) {
      final entry = byId[id];
      if (entry == null || !seen.add(id)) continue;
      ordered.add(entry);
    }
    for (final entry in entries) {
      if (seen.add(entry.id)) ordered.add(entry);
    }
    return ordered;
  }

  /// Source column shows just the account display name (no storage type) so
  /// narrow columns are not truncated.
  String _sourceLabelForConfig(RemoteStorageConfig config) {
    final name = config.displayName.trim().isNotEmpty
        ? config.displayName.trim()
        : config.storageType == StorageType.baiduPan
        ? '百度网盘'
        : config.storageType == StorageType.webdav
        ? config.webdavUsername.trim()
        : config.accessKeyId.trim();
    return name.isEmpty ? '账号' : name;
  }
}
