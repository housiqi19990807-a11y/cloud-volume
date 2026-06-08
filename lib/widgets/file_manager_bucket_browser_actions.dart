part of 'file_manager_bucket_browser.dart';

// Bucket browser action cells keep mount/unmount controls separate from list layout code.

class _BucketMountActions extends StatelessWidget {
  const _BucketMountActions({
    required this.bucket,
    required this.status,
    required this.busy,
    required this.onMountBucket,
    required this.onUnmountBucket,
    required this.onOpenMountedBucket,
    required this.moreMenuItems,
  });

  final FileManagerBucketEntry bucket;
  final BucketMountStatus? status;
  final bool busy;
  final ValueChanged<FileManagerBucketEntry>? onMountBucket;
  final ValueChanged<FileManagerBucketEntry>? onUnmountBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenMountedBucket;
  final List<Widget> moreMenuItems;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mounted = status?.mounted ?? false;
    final foreground = theme.colorScheme.primary;
    final primaryAction = mounted ? onOpenMountedBucket : onMountBucket;
    final primaryLabel = mounted ? '打开挂载目录' : '挂载';
    final primaryIcon = mounted ? LucideIcons.folderOpen : LucideIcons.link;

    if (busy) {
      return SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
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
            ),
            const SizedBox(width: 6),
            _BucketOverflowMenuButton(
              items: moreMenuItems,
              color: foreground,
              enabled: false,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _miniButton(
                label: primaryLabel,
                icon: primaryIcon,
                color: foreground,
                onPressed: primaryAction == null
                    ? null
                    : () => primaryAction(bucket),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _BucketOverflowMenuButton(
            items: moreMenuItems,
            color: foreground,
            enabled: moreMenuItems.isNotEmpty,
          ),
        ],
      ),
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

class _BucketOverflowMenuButton extends StatefulWidget {
  const _BucketOverflowMenuButton({
    required this.items,
    required this.color,
    required this.enabled,
  });

  final List<Widget> items;
  final Color color;
  final bool enabled;

  @override
  State<_BucketOverflowMenuButton> createState() =>
      _BucketOverflowMenuButtonState();
}

class _BucketOverflowMenuButtonState extends State<_BucketOverflowMenuButton> {
  final GlobalKey _buttonKey = GlobalKey();
  late final ShadContextMenuController _controller;
  Offset? _menuAnchorOffset;

  @override
  void initState() {
    super.initState();
    _controller = ShadContextMenuController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMenu() {
    final buttonContext = _buttonKey.currentContext;
    if (!mounted ||
        buttonContext == null ||
        !widget.enabled ||
        widget.items.isEmpty) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    setState(() {
      _menuAnchorOffset = topLeft + Offset(0, box.size.height + 4);
    });
    _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    return ShadContextMenu(
      anchor: _menuAnchorOffset == null
          ? null
          : ShadGlobalAnchor(_menuAnchorOffset!),
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 164),
      effects: const [],
      popoverReverseDuration: Duration.zero,
      items: widget.items,
      child: KeyedSubtree(
        key: _buttonKey,
        child: ShadIconButton.ghost(
          icon: Icon(
            LucideIcons.ellipsisVertical,
            size: 13,
            color: widget.color,
          ),
          width: 26,
          height: 26,
          iconSize: 13,
          onPressed: widget.enabled ? _showMenu : null,
        ),
      ),
    );
  }
}
