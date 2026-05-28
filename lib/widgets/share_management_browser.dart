// 分享管理列表：复用标准文件列表样式，并提供多选与行内操作。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String _shareManagementContextMenuGroup = 'share_management_browser';

class ShareManagementBrowser extends StatelessWidget {
  static const double _remainingColumnWidth = 108;
  static const double _actionColumnWidth = 144;
  static const double _trailingColumnWidth =
      FileListTile.modifiedColumnWidth + 16 + _actionColumnWidth;

  const ShareManagementBrowser({
    super.key,
    required this.records,
    required this.busyIds,
    required this.selectedIds,
    required this.onOpenRecord,
    required this.onCopyLink,
    required this.onOpenLink,
    required this.onRefreshRecord,
    required this.onDeleteRecord,
    required this.onToggleSelection,
    required this.onToggleSelectAll,
  });

  final List<ShareRecord> records;
  final Set<String> busyIds;
  final Set<String> selectedIds;
  final ValueChanged<ShareRecord> onOpenRecord;
  final ValueChanged<ShareRecord> onCopyLink;
  final ValueChanged<ShareRecord> onOpenLink;
  final ValueChanged<ShareRecord> onRefreshRecord;
  final ValueChanged<ShareRecord> onDeleteRecord;
  final ValueChanged<ShareRecord> onToggleSelection;
  final VoidCallback onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final selectableRecords = records
        .where((record) => !busyIds.contains(record.id))
        .toList(growable: false);
    final selectedCount = selectableRecords
        .where((record) => selectedIds.contains(record.id))
        .length;
    final allSelected =
        selectableRecords.isNotEmpty &&
        selectedCount == selectableRecords.length;
    final partiallySelected =
        selectedCount > 0 && selectedCount < selectableRecords.length;

    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _ShareManagementHeader(
            theme: theme,
            allSelected: allSelected,
            partiallySelected: partiallySelected,
            onToggleSelectAll: onToggleSelectAll,
          ),
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
                    trailing: _buildTrailingActions(context, record, busy),
                    onTap: () => onOpenRecord(record),
                    onDoubleTap: () => onOpenRecord(record),
                    onTitleTap: () => onOpenRecord(record),
                    onSelectionTap: busy
                        ? null
                        : () => onToggleSelection(record),
                    isSelected: selectedIds.contains(record.id),
                    showSelectionControl: true,
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

  Widget _buildTrailingActions(
    BuildContext context,
    ShareRecord record,
    bool busy,
  ) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: _trailingColumnWidth,
      child: Row(
        children: [
          SizedBox(
            width: FileListTile.modifiedColumnWidth,
            child: Text(
              busy ? '处理中...' : _formatDateTime(record.expiresAtDateTime),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: busy
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: _actionColumnWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => onOpenRecord(record),
                  child: const Text('详情'),
                ),
                const SizedBox(width: 6),
                ShadButton.destructive(
                  size: ShadButtonSize.sm,
                  onPressed: busy ? null : () => onDeleteRecord(record),
                  child: const Text('删除'),
                ),
              ],
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
          onPressed: busy
              ? null
              : () => _runMenuAction(() => onToggleSelection(record)),
          child: Text(selectedIds.contains(record.id) ? '取消选择' : '选择'),
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
  const _ShareManagementHeader({
    required this.theme,
    required this.allSelected,
    required this.partiallySelected,
    required this.onToggleSelectAll,
  });

  final ShadThemeData theme;
  final bool allSelected;
  final bool partiallySelected;
  final VoidCallback onToggleSelectAll;

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
          _HeaderSelectionIndicator(
            allSelected: allSelected,
            partiallySelected: partiallySelected,
            onTap: onToggleSelectAll,
          ),
          const SizedBox(width: 10),
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
          const SizedBox(width: 16),
          SizedBox(
            width: ShareManagementBrowser._actionColumnWidth,
            child: Text('操作', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _HeaderSelectionIndicator extends StatelessWidget {
  const _HeaderSelectionIndicator({
    required this.allSelected,
    required this.partiallySelected,
    required this.onTap,
  });

  final bool allSelected;
  final bool partiallySelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: allSelected || partiallySelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: allSelected || partiallySelected
                ? accent
                : theme.colorScheme.border.withValues(alpha: 0.9),
            width: 1.2,
          ),
        ),
        child: allSelected
            ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
            : partiallySelected
            ? const Icon(LucideIcons.minus, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
