part of 'file_manager_page.dart';

// 文件管理页来源聚合：把多个账号的 bucket 列表合并成统一首页。

extension _FileManagerPageSources on _FileManagerPageState {
  Future<List<FileManagerBucketEntry>> _loadBucketEntries() async {
    final sources = await _loadBucketSources();
    final entries = <FileManagerBucketEntry>[];
    for (final source in sources) {
      final buckets = await widget.api.listBuckets(source.config);
      for (final bucket in buckets) {
        entries.add(
          FileManagerBucketEntry.fromBucketInfo(
            bucket: bucket,
            profileName: source.profileName,
            sourceLabel: source.sourceLabel,
            config: source.config,
          ),
        );
      }
    }
    final order = await widget.api.listBucketOrder();
    if (order.isNotEmpty) {
      final byId = {for (final entry in entries) entry.id: entry};
      final ordered = <FileManagerBucketEntry>[];
      final seen = <String>{};
      for (final id in order) {
        final entry = byId[id];
        if (entry == null || !seen.add(id)) {
          continue;
        }
        ordered.add(entry);
      }
      for (final entry in entries) {
        if (seen.add(entry.id)) {
          ordered.add(entry);
        }
      }
      return ordered;
    }
    // Default: account list order (sources already follow profile order), then
    // bucket name within each account.
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
      return left.bucket.name.compareTo(right.bucket.name);
    });
    return entries;
  }

  Future<List<_BucketSourceConfig>> _loadBucketSources() async {
    if (widget.profiles.isEmpty) {
      return <_BucketSourceConfig>[
        _BucketSourceConfig(
          profileName: 'default',
          sourceLabel: _sourceLabelForConfig(widget.config),
          config: widget.config,
        ),
      ];
    }
    return Future.wait(
      widget.profiles.map((profile) async {
        final config = await widget.api.loadProfile(profile.name);
        return _BucketSourceConfig(
          profileName: profile.name,
          sourceLabel: _sourceLabelForConfig(config),
          config: config,
        );
      }),
    );
  }

  /// 来源列仅展示账号/显示名称，不拼接存储类型（避免窄列被省略号截断）。
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

class _BucketSourceConfig {
  const _BucketSourceConfig({
    required this.profileName,
    required this.sourceLabel,
    required this.config,
  });

  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
}
