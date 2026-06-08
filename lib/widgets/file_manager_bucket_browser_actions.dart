part of 'file_manager_bucket_browser.dart';

// Bucket browser action cells keep mount/unmount controls separate from list layout code.

class _BucketMountActions extends StatelessWidget {
  static const double _actionSlotWidth = 104;

  const _BucketMountActions({
    required this.bucket,
    required this.status,
    required this.busy,
    required this.onMountBucket,
    required this.onUnmountBucket,
    required this.onOpenMountedBucket,
    required this.onConfigureBucket,
  });

  final FileManagerBucketEntry bucket;
  final BucketMountStatus? status;
  final bool busy;
  final ValueChanged<FileManagerBucketEntry>? onMountBucket;
  final ValueChanged<FileManagerBucketEntry>? onUnmountBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenMountedBucket;
  final ValueChanged<FileManagerBucketEntry>? onConfigureBucket;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mounted = status?.mounted ?? false;
    final foreground = theme.colorScheme.primary;
    final primaryAction = mounted ? onOpenMountedBucket : onMountBucket;
    final primaryLabel = mounted ? '打开挂载目录' : '挂载';
    final primaryIcon = mounted ? LucideIcons.folderOpen : LucideIcons.link;
    final secondaryAction = mounted ? onUnmountBucket : onConfigureBucket;
    final secondaryLabel = mounted ? '卸载' : '配置';
    final secondaryIcon = mounted ? LucideIcons.x : LucideIcons.settings2;

    if (busy) {
      return SizedBox(
        height: 32,
        child: Row(
          children: [
            _actionSlot(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: AppLoadingIndicator(
                      strokeWidth: 1.5,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '处理中',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _actionSlot(
              _miniButton(
                label: secondaryLabel,
                icon: secondaryIcon,
                color: foreground,
                onPressed: null,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          _actionSlot(
            _miniButton(
              label: primaryLabel,
              icon: primaryIcon,
              color: foreground,
              onPressed: primaryAction == null
                  ? null
                  : () => primaryAction(bucket),
            ),
          ),
          const SizedBox(width: 6),
          _actionSlot(
            _miniButton(
              label: secondaryLabel,
              icon: secondaryIcon,
              color: foreground,
              onPressed: secondaryAction == null
                  ? null
                  : () => secondaryAction(bucket),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionSlot(Widget child) {
    return SizedBox(
      width: _actionSlotWidth,
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  Widget _miniButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ],
      ),
    );
  }
}
