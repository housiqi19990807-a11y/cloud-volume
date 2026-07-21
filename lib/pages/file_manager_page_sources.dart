part of 'file_manager_page.dart';

// File-manager home page used to own the only copy of the multi-account
// bucket aggregation pipeline. That logic now lives in BucketSourceService
// so the global trash page (and any future surface) sees the same bucket
// set. This extension is now a thin adapter that forwards to the service
// while preserving the file-manager-specific private exception type, which
// _FileManagerPageBucketLoading catches to surface a "reconfigure this
// account" action.
extension _FileManagerPageSources on _FileManagerPageState {
  Future<List<FileManagerBucketEntry>> _loadBucketEntries() async {
    try {
      return BucketSourceService.instance.loadEntries(
        widget.api,
        widget.profiles,
        fallbackConfig: widget.config,
      );
    } on BucketSourceLoadException catch (error, stackTrace) {
      // Re-wrap into the file manager's private type so existing catch sites
      // keep resolving on the private name without touching them.
      Error.throwWithStackTrace(
        _BucketSourceLoadException(error.profileName, error.cause),
        stackTrace,
      );
    }
  }
}

class _BucketSourceLoadException implements Exception {
  const _BucketSourceLoadException(this.profileName, this.cause);

  final String profileName;
  final Object cause;

  @override
  String toString() => cause.toString();
}

