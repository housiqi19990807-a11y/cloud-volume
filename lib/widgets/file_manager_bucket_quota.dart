part of 'file_manager_bucket_browser.dart';

// Bucket quota labels share provider usage while adapting to list and grid widths.
extension FileManagerBucketQuota on FileManagerBucketBrowser {
  String _bucketQuotaLabel(
    FileManagerBucketEntry bucket, {
    bool includePrefix = false,
  }) {
    final customBytes = bucket.config
        .bucketSettingsFor(bucket.bucket.name)
        .customQuotaBytes;
    final bytes = customBytes > 0 ? customBytes : bucket.bucket.quotaBytes;
    if (bytes <= 0) return includePrefix ? '' : '--';
    final value = includePrefix
        ? _compactQuotaLabel(bucket, bytes)
        : _fullQuotaLabel(bucket, bytes);
    return includePrefix ? '配额 $value' : value;
  }

  String _fullQuotaLabel(FileManagerBucketEntry bucket, int totalBytes) {
    if (!bucket.bucket.quotaKnown) return formatBytes(totalBytes);
    return '${formatBytes(bucket.bucket.usedBytes)} / ${formatBytes(totalBytes)}';
  }

  String _compactQuotaLabel(FileManagerBucketEntry bucket, int totalBytes) {
    if (!bucket.bucket.quotaKnown) return formatBytes(totalBytes);
    final unit = _quotaUnit(totalBytes);
    final scale = _quotaUnitScale(unit);
    final used = (bucket.bucket.usedBytes / scale).toStringAsFixed(1);
    final total = (totalBytes / scale).toStringAsFixed(1);
    return '$used/$total $unit';
  }

  String _quotaUnit(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) return 'TB';
    if (bytes >= 1024 * 1024 * 1024) return 'GB';
    if (bytes >= 1024 * 1024) return 'MB';
    if (bytes >= 1024) return 'KB';
    return 'B';
  }

  double _quotaUnitScale(String unit) {
    return switch (unit) {
      'TB' => 1024 * 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'MB' => 1024 * 1024,
      'KB' => 1024,
      _ => 1,
    };
  }
}
