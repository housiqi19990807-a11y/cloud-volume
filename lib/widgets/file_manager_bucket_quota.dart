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
    if (!includePrefix) return _fullQuotaLabel(bucket, bytes);
    if (!bucket.bucket.quotaKnown) return '配额 ${formatBytes(bytes)}';
    return '已用 ${_compactQuotaLabel(bucket, bytes)}';
  }

  String _fullQuotaLabel(FileManagerBucketEntry bucket, int totalBytes) {
    if (!bucket.bucket.quotaKnown) return '-- / ${formatBytes(totalBytes)}';
    return '${formatBytes(bucket.bucket.usedBytes)} / ${formatBytes(totalBytes)}';
  }

  Widget _bucketQuotaUsage(
    BuildContext context,
    FileManagerBucketEntry bucket,
  ) {
    final theme = ShadTheme.of(context);
    final customBytes = bucket.config
        .bucketSettingsFor(bucket.bucket.name)
        .customQuotaBytes;
    final totalBytes = customBytes > 0 ? customBytes : bucket.bucket.quotaBytes;
    if (totalBytes <= 0) {
      return _quotaValueText('--', theme.colorScheme.mutedForeground);
    }
    final label = _fullQuotaLabel(bucket, totalBytes);
    if (!bucket.bucket.quotaKnown) {
      return _quotaValueText(label, theme.colorScheme.mutedForeground);
    }
    final progress = (bucket.bucket.usedBytes / totalBytes).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final progressColor = progress >= 0.95
        ? theme.colorScheme.destructive
        : theme.colorScheme.primary;
    return AppTooltip(
      message:
          '已用 ${formatBytes(bucket.bucket.usedBytes)}，总配额 ${formatBytes(totalBytes)}（$percent%）',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _quotaValueText(label, theme.colorScheme.mutedForeground),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: theme.colorScheme.border.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quotaValueText(String value, Color color) {
    return Text(
      value,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 11, color: color),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _compactQuotaLabel(FileManagerBucketEntry bucket, int totalBytes) {
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
