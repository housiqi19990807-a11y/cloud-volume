// 文件列表表头：负责名称/大小/修改时间列，以及多选模式下的全选勾选控件。

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerObjectHeader extends StatelessWidget {
  const FileManagerObjectHeader({
    super.key,
    required this.theme,
    required this.showSelectionControl,
    required this.allSelected,
    required this.partiallySelected,
    required this.onToggleSelectAll,
  });

  final ShadThemeData theme;
  final bool showSelectionControl;
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
          if (showSelectionControl) ...[
            _HeaderSelectionIndicator(
              allSelected: allSelected,
              partiallySelected: partiallySelected,
              onTap: onToggleSelectAll,
            ),
            const SizedBox(width: 10),
          ],
          const SizedBox(width: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('名称', style: labelStyle)),
          const SizedBox(width: 12),
          SizedBox(
            width: FileListTile.sizeColumnWidth,
            child: Text('大小', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: FileListTile.modifiedColumnWidth,
            child: Text('修改时间', textAlign: TextAlign.right, style: labelStyle),
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
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : partiallySelected
            ? const Icon(Icons.remove, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
