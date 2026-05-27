// Global trash controls keep filtering and batch-action UI out of the page file.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String allBucketsFilter = '__all_buckets__';

enum TrashTypeFilter {
  all('全部类型'),
  files('仅文件'),
  directories('仅目录');

  const TrashTypeFilter(this.label);

  final String label;
}

class GlobalTrashFilters extends StatelessWidget {
  const GlobalTrashFilters({
    super.key,
    required this.searchController,
    required this.bucketFilter,
    required this.bucketOptions,
    required this.typeFilter,
    required this.allFilteredSelected,
    required this.partiallySelected,
    required this.loading,
    required this.onBucketChanged,
    required this.onTypeChanged,
    required this.onToggleSelectAll,
  });

  final TextEditingController searchController;
  final String bucketFilter;
  final List<String> bucketOptions;
  final TrashTypeFilter typeFilter;
  final bool allFilteredSelected;
  final bool partiallySelected;
  final bool loading;
  final ValueChanged<String?> onBucketChanged;
  final ValueChanged<TrashTypeFilter?> onTypeChanged;
  final ValueChanged<bool?> onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: searchController,
            placeholder: const Text('搜索名称、原路径或存储桶'),
          ),
        ),
        const SizedBox(width: 12),
        _dropdown<String>(
          value: bucketFilter,
          items: bucketOptions,
          labelBuilder: (value) => value == allBucketsFilter ? '全部存储桶' : value,
          onChanged: onBucketChanged,
          width: 170,
        ),
        const SizedBox(width: 12),
        _dropdown<TrashTypeFilter>(
          value: typeFilter,
          items: TrashTypeFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: onTypeChanged,
          width: 130,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 48,
          child: Checkbox(
            value: allFilteredSelected
                ? true
                : partiallySelected
                ? null
                : false,
            tristate: true,
            onChanged: loading ? null : onToggleSelectAll,
          ),
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
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
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

class GlobalTrashSelectionBar extends StatelessWidget {
  const GlobalTrashSelectionBar({
    super.key,
    required this.selectedCount,
    required this.onRestoreSelected,
    required this.onDeleteSelected,
    required this.onClearSelection,
  });

  final int selectedCount;
  final VoidCallback onRestoreSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '已选 $selectedCount 项',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: onRestoreSelected,
            child: const Text('批量恢复'),
          ),
          const SizedBox(width: 8),
          ShadButton.destructive(
            size: ShadButtonSize.sm,
            onPressed: onDeleteSelected,
            child: const Text('批量彻底删除'),
          ),
          const Spacer(),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: onClearSelection,
            child: const Text('清空选择'),
          ),
        ],
      ),
    );
  }
}
