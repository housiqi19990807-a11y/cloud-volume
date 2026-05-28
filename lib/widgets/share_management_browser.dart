// 分享管理列表：复用标准文件列表样式，只在主列表展示摘要信息。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _shareManagementContextMenuGroup = 'share_management_browser';

class ShareManagementBrowser extends StatelessWidget {
  static const double _remainingColumnWidth = 108;

  const ShareManagementBrowser({
    super.key,
    required this.records,
    required this.busyIds,
    required this.onOpenRecord,
    required this.onCopyLink,
    required this.onOpenLink,
    required this.onRefreshRecord,
    required this.onDeleteRecord,
  });

  final List<ShareRecord> records;
  final Set<String> busyIds;
  final ValueChanged<ShareRecord> onOpenRecord;
  final ValueChanged<ShareRecord> onCopyLink;
  final ValueChanged<ShareRecord> onOpenLink;
  final ValueChanged<ShareRecord> onRefreshRecord;
  final ValueChanged<ShareRecord> onDeleteRecord;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _ShareManagementHeader(theme: theme),
          Expanded(
            child: ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                final busy = busyIds.contains(record.id);
                return _wrapWithContextMenu(
                  record,
                  busy,
                  FileListTile(
                    leading: LocalCloudPanFileIcon(
                      name: record.name,
                      isDirectory: record.key.endsWith('/'),
                      size: 32,
                    ),
                    title: record.name,
                    subtitleLabel: '${record.bucket} / ${record.key}',
                    sizeLabel: _remainingText(record),
                    sizeColumnWidthOverride: _remainingColumnWidth,
                    modifiedLabel: busy
                        ? '处理中...'
                        : _formatDateTime(record.expiresAtDateTime),
                    onTap: () => onOpenRecord(record),
                    onDoubleTap: () => onOpenRecord(record),
                    onTitleTap: () => onOpenRecord(record),
                    showDivider: index != records.length - 1,
                    deleting: busy,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapWithContextMenu(ShareRecord record, bool busy, Widget child) {
    return DesktopContextMenuRegion(
      groupId: _shareManagementContextMenuGroup,
      items: [
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onOpenRecord(record)),
          child: const Text('查看详情'),
        ),
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onCopyLink(record)),
          child: const Text('复制链接'),
        ),
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onOpenLink(record)),
          child: const Text('打开链接'),
        ),
        ShadContextMenuItem(
          onPressed: busy
              ? null
              : () => _runMenuAction(() => onRefreshRecord(record)),
          child: Text(busy ? '处理中...' : '更新有效时间'),
        ),
        ShadContextMenuItem(
          onPressed: busy
              ? null
              : () => _runMenuAction(() => onDeleteRecord(record)),
          child: const Text('删除记录'),
        ),
      ],
      child: child,
    );
  }

  void _runMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_shareManagementContextMenuGroup);
    action();
  }

  static String _remainingText(ShareRecord record) {
    final expiresAt = record.expiresAtDateTime;
    if (expiresAt == null) {
      return '未知';
    }
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return '已过期';
    }
    if (remaining.inDays >= 1) {
      return '${remaining.inDays} 天';
    }
    if (remaining.inHours >= 1) {
      return '${remaining.inHours} 小时';
    }
    if (remaining.inMinutes >= 1) {
      return '${remaining.inMinutes} 分钟';
    }
    return '即将过期';
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '--';
    }
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _ShareManagementHeader extends StatelessWidget {
  const _ShareManagementHeader({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.7);
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('名称', style: labelStyle)),
          const SizedBox(width: 12),
          SizedBox(
            width: ShareManagementBrowser._remainingColumnWidth,
            child: Text('剩余时间', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: FileListTile.modifiedColumnWidth,
            child: Text('到期时间', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}
