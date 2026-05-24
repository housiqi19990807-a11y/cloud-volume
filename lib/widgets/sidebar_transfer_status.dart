// 侧边栏传输状态入口：显示实时速度、运行动画和 hover 悬浮任务列表。

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/widgets/fluent_system_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SidebarTransferStatus extends StatefulWidget {
  const SidebarTransferStatus({
    super.key,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  @override
  State<SidebarTransferStatus> createState() => _SidebarTransferStatusState();
}

class _SidebarTransferStatusState extends State<SidebarTransferStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    TransferQueue.instance.addListener(_syncAnimation);
    _syncAnimation();
  }

  @override
  void dispose() {
    TransferQueue.instance.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (!mounted) return;
    if (TransferQueue.instance.hasRunning) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final queue = TransferQueue.instance;
    final foreground = queue.hasRunning ? widget.accent : widget.muted;
    final badgeCount = queue.runningCount;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hovered)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: _TransferHoverCard(theme: theme),
            ),
          AnimatedBuilder(
            animation: queue,
            builder: (context, _) {
              return GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: queue.hasRunning
                        ? widget.accent.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: queue.hasRunning
                          ? widget.accent.withValues(alpha: 0.18)
                          : theme.colorScheme.border.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ScaleTransition(
                            scale: Tween<double>(begin: 1, end: 1.08).animate(
                              CurvedAnimation(
                                parent: _controller,
                                curve: Curves.easeInOut,
                              ),
                            ),
                            child: Opacity(
                              opacity: queue.hasRunning ? 1 : 0.9,
                              child: FluentSystemIcon(
                                glyph: FluentSystemGlyph.transfers,
                                size: 16,
                                color: foreground,
                              ),
                            ),
                          ),
                          if (badgeCount > 0)
                            Positioned(
                              right: -9,
                              top: -8,
                              child: _TransferTaskBadge(
                                count: badgeCount,
                                accent: widget.accent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '上传下载',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: foreground,
                                  ),
                                ),
                                if (badgeCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '$badgeCount 项',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: widget.accent,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              queue.speedSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TransferTaskBadge extends StatelessWidget {
  const _TransferTaskBadge({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _TransferHoverCard extends StatelessWidget {
  const _TransferHoverCard({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tasks = TransferQueue.instance.tasks.take(6).toList();
    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(14),
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.border.withValues(alpha: 0.7),
          ),
        ),
        child: tasks.isEmpty
            ? Text(
                '暂无上传或下载任务',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final task in tasks) _TransferHoverRow(task: task),
                ],
              ),
      ),
    );
  }
}

class _TransferHoverRow extends StatelessWidget {
  const _TransferHoverRow({required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = task.isUpload
        ? const Color(0xff2563eb)
        : const Color(0xff0f766e);
    final detail = task.status == TransferStatus.failed
        ? (task.error ?? '${task.typeLabel}失败')
        : task.totalBytes > 0
        ? '${formatBytes(task.bytesCompleted)} / ${formatBytes(task.totalBytes)}'
        : task.typeLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            task.isUpload ? LucideIcons.upload : LucideIcons.download,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            switch (task.status) {
              TransferStatus.pending => '等待',
              TransferStatus.running => formatBytesPerSecond(task.speedBytes),
              TransferStatus.done => '完成',
              TransferStatus.failed => '失败',
            },
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: task.status == TransferStatus.failed
                  ? theme.colorScheme.destructive
                  : task.status == TransferStatus.done
                  ? const Color(0xff15803d)
                  : theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
