part of 'file_manager_bucket_browser.dart';

// Bucket quota helpers render provider/custom usage in list mode only.
extension FileManagerBucketQuota on FileManagerBucketBrowser {
  String _fullQuotaLabel(FileManagerBucketEntry bucket, int totalBytes) {
    if (!bucket.bucket.quotaKnown) return '用量未知 · ${formatBytes(totalBytes)}';
    return '${formatBytes(bucket.bucket.usedBytes)} / ${formatBytes(totalBytes)}';
  }

  Widget _bucketQuotaUsage(
    BuildContext context,
    FileManagerBucketEntry bucket,
  ) {
    final theme = ShadTheme.of(context);
    final totalBytes = _quotaTotalBytes(bucket);
    if (totalBytes <= 0) {
      return AppTooltip(
        message: '尚未设置总额度，可在桶设置中配置自定义额度',
        child: _quotaUsageColumn(
          theme: theme,
          label: '未设置额度',
          progress: 0,
          progressColor: theme.colorScheme.mutedForeground,
        ),
      );
    }
    final label = _fullQuotaLabel(bucket, totalBytes);
    final progress = _quotaProgress(bucket, totalBytes);
    final percent = (progress * 100).round();
    final progressColor = bucket.bucket.quotaKnown && progress >= 0.95
        ? theme.colorScheme.destructive
        : theme.colorScheme.primary;
    return AppTooltip(
      message: bucket.bucket.quotaKnown
          ? '已用 ${formatBytes(bucket.bucket.usedBytes)}，总配额 ${formatBytes(totalBytes)}（$percent%）'
          : '总配额 ${formatBytes(totalBytes)}；服务端未提供已用空间',
      child: _quotaUsageColumn(
        theme: theme,
        label: label,
        progress: progress,
        progressColor: progressColor,
      ),
    );
  }

  Widget _quotaUsageColumn({
    required ShadThemeData theme,
    required String label,
    required double progress,
    required Color progressColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _quotaValueText(label, theme.colorScheme.mutedForeground),
        const SizedBox(height: 4),
        _quotaProgressBar(
          theme: theme,
          progress: progress,
          progressColor: progressColor,
        ),
      ],
    );
  }

  Widget _quotaProgressBar({
    required ShadThemeData theme,
    required double progress,
    required Color progressColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 3,
        backgroundColor: theme.colorScheme.border.withValues(alpha: 0.6),
        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
      ),
    );
  }

  int _quotaTotalBytes(FileManagerBucketEntry bucket) {
    final customBytes = bucket.config
        .bucketSettingsFor(bucket.bucket.name)
        .customQuotaBytes;
    return customBytes > 0 ? customBytes : bucket.bucket.quotaBytes;
  }

  double _quotaProgress(FileManagerBucketEntry bucket, int totalBytes) {
    if (totalBytes <= 0 || !bucket.bucket.quotaKnown) return 0;
    return (bucket.bucket.usedBytes / totalBytes).clamp(0.0, 1.0);
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
}
