// Global trash controls keep filtering and fixed header actions out of the page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/page_header_actions.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A bucket option for the trash filter dropdown: the internal id used to
/// switch buckets plus the user-facing label (display name when set, real
/// bucket name otherwise). Kept here so the control does not depend on the
/// file-manager bucket entry model.
class GlobalTrashBucketOption {
  const GlobalTrashBucketOption({required this.id, required this.label});

  final String id;
  final String label;
}

class GlobalTrashFilters extends StatelessWidget {
  const GlobalTrashFilters({
    super.key,
    required this.searchController,
    required this.bucketFilter,
    required this.bucketOptions,
    required this.onBucketChanged,
  });

  final TextEditingController searchController;
  final String bucketFilter;
  final List<GlobalTrashBucketOption> bucketOptions;
  final ValueChanged<String?> onBucketChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: searchController,
            placeholder: const Text('搜索名称或原路径'),
          ),
        ),
        const SizedBox(width: 12),
        _dropdown<String>(
          value: bucketFilter,
          items: bucketOptions.map((option) => option.id).toList(),
          labelBuilder: (id) {
            final match = bucketOptions.firstWhere(
              (option) => option.id == id,
              orElse: () => GlobalTrashBucketOption(id: id, label: id),
            );
            return match.label;
          },
          onChanged: onBucketChanged,
          width: 170,
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T value) labelBuilder,
    required ValueChanged<T?> onChanged,
    required double width,
  }) {
    // Do NOT pass a ValueKey(value) here: forcing the ShadSelect to rebuild on
    // every selection causes its internal ShadGestureDetector/MouseRegion to
    // miss onExit while the pointer is still over it, leaving the cursor stuck
    // on the pointing hand after navigating away (especially under IndexedStack
    // where the trash page stays mounted but hidden). ShadSelect already
    // reflects the current selection via initialValue + selectedOptionBuilder.
    return SizedBox(
      width: width,
      child: ShadSelect<T>(
        minWidth: width,
        initialValue: value,
        placeholder: Text(
          value.toString().isEmpty ? '选择存储桶' : labelBuilder(value),
        ),
        selectedOptionBuilder: (context, selected) =>
            Text(labelBuilder(selected), overflow: TextOverflow.ellipsis),
        options: items
            .map(
              (item) => ShadOption<T>(
                value: item,
                child: Text(
                  labelBuilder(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }
}

class GlobalTrashHeaderActions extends StatelessWidget {
  const GlobalTrashHeaderActions({
    super.key,
    required this.selectedCount,
    required this.loading,
    required this.onRefresh,
    required this.onRestoreSelected,
    required this.onDeleteSelected,
    required this.onClearTrash,
    required this.onClearSelection,
  });

  final int selectedCount;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onRestoreSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback? onClearTrash;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasSelection = selectedCount > 0;

    if (!hasSelection) {
      // 未选中：刷新为主操作，清空回收站在宽度不足时收进菜单。
      return PageHeaderActions(
        primary: [
          ShadButton.outline(
            onPressed: loading ? null : onRefresh,
            child: const Text('刷新'),
          ),
        ],
        secondary: [
          SecondaryAction(
            label: '清空回收站',
            onPressed: loading ? null : onClearTrash,
            enabled: !(loading || onClearTrash == null),
            builder: (_) => ShadButton.destructive(
              onPressed: loading ? null : onClearTrash,
              child: const Text('清空回收站'),
            ),
          ),
        ],
      );
    }

    // 选中：徽标 + 批量恢复 + 批量彻底删除为主操作，清空选择为次操作。
    return PageHeaderActions(
      primary: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '已选 $selectedCount 项',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: hasSelection ? onRestoreSelected : null,
          child: const Text('批量恢复'),
        ),
        ShadButton.destructive(
          size: ShadButtonSize.sm,
          onPressed: hasSelection ? onDeleteSelected : null,
          child: const Text('批量彻底删除'),
        ),
      ],
      secondary: [
        SecondaryAction(
          label: '清空选择',
          onPressed: hasSelection ? onClearSelection : null,
          enabled: hasSelection,
          builder: (_) => ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: hasSelection ? onClearSelection : null,
            child: const Text('清空选择'),
          ),
        ),
      ],
    );
  }
}
