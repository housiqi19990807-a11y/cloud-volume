part of 'global_trash_page.dart';

// 回收站分页辅助类型：把首次桶探测结果从主页面文件中拆出，保持页面文件精简。

class _BucketTrashLoadResult {
  const _BucketTrashLoadResult({
    required this.bucket,
    required this.page,
    required this.entries,
  });

  final String bucket;
  final TrashListPage page;
  final List<GlobalTrashBrowserEntry> entries;
}
