part of 'file_manager_page.dart';

// File-manager home page used to own the only copy of the multi-account
// bucket aggregation pipeline. That logic now lives in BucketSourceService
// so the global trash page (and any future surface) sees the same bucket
// set. This extension is now a thin adapter that forwards to the service
// while preserving the file-manager-specific private exception type, which
// _FileManagerPageBucketLoading catches to surface a "reconfigure this
// account" action.
extension _FileManagerPageSources on _FileManagerPageState {
  Future<BucketSourceLoadResult> _loadBucketEntries() {
    return BucketSourceService.instance.loadEntriesWithFailures(
      widget.api,
      widget.profiles,
      fallbackConfig: widget.config,
    );
  }
}
