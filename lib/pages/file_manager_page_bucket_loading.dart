// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// Bucket loading applies only the newest request and keeps source errors profile-aware.
extension _FileManagerPageBucketLoading on _FileManagerPageState {
  Future<bool> _loadBuckets() async {
    final generation = ++_bucketQuotaRefreshGeneration;
    _beginLoading(message: '加载存储桶...');
    try {
      // Fetch bucket entries, then resolve quotas inline so a single setState
      // renders the final list. A separate post-frame quota refresh would replace
      // _buckets and destroy FileListTile hover state (the "hover又坏了" bug).
      final baseEntries = _applyCachedBucketQuotas(
        await _loadBucketEntries(),
      );
      if (!mounted || generation != _bucketQuotaRefreshGeneration) {
        return false;
      }
      final entriesWithQuota = await _populateBucketQuotas(
        baseEntries,
        generation,
      );
      if (!mounted || generation != _bucketQuotaRefreshGeneration) {
        return false;
      }
      setState(() {
        _failedBucketProfileName = null;
        _objectListingCache.clear();
        _buckets = entriesWithQuota;
        _activeBucketEntry = null;
        _objects = null;
        _trashItems = null;
        _prefix = '';
        _breadcrumbs = [];
        _showTrash = false;
        _objectsNextToken = '';
        _objectsHasMore = false;
        _pagingObjects = false;
        _directoryAccess = null;
        _checkingDirectoryAccess = false;
        _trashNextToken = '';
        _trashHasMore = false;
        _pagingTrash = false;
        _bucketMountStatuses.clear();
        _mountBusyBuckets.clear();
        _selectedObjectKeys.clear();
        _deletingObjectKeys.clear();
        _endLoading();
      });
      if (_contentScrollController.hasClients) {
        _contentScrollController.jumpTo(0);
      }
      if (entriesWithQuota.isNotEmpty) {
        unawaited(_refreshBucketMountStatuses(entriesWithQuota));
      }
      return true;
    } catch (error) {
      if (!mounted || generation != _bucketQuotaRefreshGeneration) {
        return false;
      }
      final sourceError = error is _BucketSourceLoadException ? error : null;
      setState(() {
        _failedBucketProfileName = sourceError?.profileName;
        _error = describeBridgeError(sourceError?.cause ?? error);
        _endLoading();
      });
      return false;
    }
  }
}
