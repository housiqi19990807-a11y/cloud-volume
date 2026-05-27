// 全局回收站页：跨所有存储桶聚合软删除项目，支持筛选与批量恢复/删除。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:remote_storage/widgets/global_trash_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class GlobalTrashPage extends StatefulWidget {
  const GlobalTrashPage({super.key, required this.api, required this.config});

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

  @override
  State<GlobalTrashPage> createState() => _GlobalTrashPageState();
}

class _GlobalTrashPageState extends State<GlobalTrashPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _busyEntries = <String>{};
  final Set<String> _selectedIds = <String>{};
  List<_GlobalTrashEntry> _entries = const <_GlobalTrashEntry>[];
  String _searchText = '';
  String _bucketFilter = allBucketsFilter;
  TrashTypeFilter _typeFilter = TrashTypeFilter.all;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
    unawaited(_loadEntries());
  }

  @override
  void didUpdateWidget(covariant GlobalTrashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      unawaited(_loadEntries());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_GlobalTrashEntry> get _filteredEntries {
    return _entries
        .where((entry) {
          if (_bucketFilter != allBucketsFilter &&
              entry.bucket != _bucketFilter) {
            return false;
          }
          switch (_typeFilter) {
            case TrashTypeFilter.files:
              if (entry.item.isDir) return false;
            case TrashTypeFilter.directories:
              if (!entry.item.isDir) return false;
            case TrashTypeFilter.all:
              break;
          }
          if (_searchText.isEmpty) {
            return true;
          }
          final haystack = <String>[
            entry.item.name,
            entry.item.originalKey,
            entry.bucket,
          ].join('\n').toLowerCase();
          return haystack.contains(_searchText);
        })
        .toList(growable: false);
  }

  List<String> get _bucketOptions {
    final buckets =
        _entries.map((entry) => entry.bucket).toSet().toList(growable: false)
          ..sort();
    return <String>[allBucketsFilter, ...buckets];
  }

  int get _selectedFilteredCount {
    return _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .length;
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buckets = await widget.api.listBuckets(widget.config);
      final itemsPerBucket = await Future.wait(
        buckets.map((bucket) async {
          final items = await widget.api.listTrash(widget.config, bucket.name);
          return items
              .map((item) => _GlobalTrashEntry(bucket: bucket.name, item: item))
              .toList(growable: false);
        }),
      );
      final merged = itemsPerBucket.expand((items) => items).toList();
      merged.sort((left, right) {
        final leftTime = left.deletedAtDateTime;
        final rightTime = right.deletedAtDateTime;
        if (leftTime == null && rightTime == null) {
          return left.item.name.compareTo(right.item.name);
        }
        if (leftTime == null) return 1;
        if (rightTime == null) return -1;
        return rightTime.compareTo(leftTime);
      });
      if (!mounted) return;
      setState(() {
        _entries = merged;
        _selectedIds.removeWhere(
          (id) => !_entries.any((entry) => entry.id == id),
        );
        if (_bucketFilter != allBucketsFilter &&
            !_entries.any((entry) => entry.bucket == _bucketFilter)) {
          _bucketFilter = allBucketsFilter;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restoreEntry(_GlobalTrashEntry entry) async {
    await _runBusy(<_GlobalTrashEntry>[entry], () async {
      await widget.api.restoreTrashItem(
        widget.config,
        entry.bucket,
        entry.item.id,
      );
      await _loadEntries();
    });
  }

  Future<void> _deleteEntry(_GlobalTrashEntry entry) async {
    final confirmed = await showDeleteTrashItemDialog(context, entry.item);
    if (!confirmed) return;
    await _runBusy(<_GlobalTrashEntry>[entry], () async {
      await widget.api.deleteTrashItem(
        widget.config,
        entry.bucket,
        entry.item.id,
      );
      await _loadEntries();
    });
  }

  Future<void> _restoreSelected() async {
    final targets = _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    await _runBusy(targets, () async {
      for (final entry in targets) {
        await widget.api.restoreTrashItem(
          widget.config,
          entry.bucket,
          entry.item.id,
        );
      }
      await _loadEntries();
    });
  }

  Future<void> _deleteSelected() async {
    final targets = _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final confirmed = await showDeleteTrashItemsDialog(context, targets.length);
    if (!confirmed) return;
    await _runBusy(targets, () async {
      for (final entry in targets) {
        await widget.api.deleteTrashItem(
          widget.config,
          entry.bucket,
          entry.item.id,
        );
      }
      await _loadEntries();
    });
  }

  Future<void> _runBusy(
    List<_GlobalTrashEntry> entries,
    Future<void> Function() action,
  ) async {
    setState(() {
      for (final entry in entries) {
        _busyEntries.add(entry.id);
        _selectedIds.remove(entry.id);
      }
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          for (final entry in entries) {
            _busyEntries.remove(entry.id);
          }
        });
      }
    }
  }

  void _toggleSelectAllFiltered(bool nextValue) {
    final shouldSelect = nextValue;
    setState(() {
      for (final entry in _filteredEntries) {
        if (_busyEntries.contains(entry.id)) continue;
        if (shouldSelect) {
          _selectedIds.add(entry.id);
        } else {
          _selectedIds.remove(entry.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final filteredEntries = _filteredEntries;
    final selectedFilteredCount = _selectedFilteredCount;
    final allFilteredSelected =
        filteredEntries.isNotEmpty &&
        selectedFilteredCount == filteredEntries.length;
    final partiallySelected = selectedFilteredCount > 0 && !allFilteredSelected;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '回收站',
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '跨所有存储桶统一管理已删除项目，可筛选、批量恢复或批量彻底删除。',
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ShadButton.outline(
                onPressed: _loading ? null : () => unawaited(_loadEntries()),
                child: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlobalTrashFilters(
            searchController: _searchController,
            bucketFilter: _bucketFilter,
            bucketOptions: _bucketOptions,
            typeFilter: _typeFilter,
            allFilteredSelected: allFilteredSelected,
            partiallySelected: partiallySelected,
            loading: _loading,
            onBucketChanged: (value) {
              if (value == null) return;
              setState(() => _bucketFilter = value);
            },
            onTypeChanged: (value) {
              if (value == null) return;
              setState(() => _typeFilter = value);
            },
            onToggleSelectAll: _toggleSelectAllFiltered,
          ),
          const SizedBox(height: 16),
          if (selectedFilteredCount > 0) ...[
            GlobalTrashSelectionBar(
              selectedCount: selectedFilteredCount,
              onRestoreSelected: () => unawaited(_restoreSelected()),
              onDeleteSelected: () => unawaited(_deleteSelected()),
              onClearSelection: () => setState(() => _selectedIds.clear()),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(child: _buildBody(theme, filteredEntries)),
        ],
      ),
    );
  }

  Widget _buildBody(
    ShadThemeData theme,
    List<_GlobalTrashEntry> filteredEntries,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 40,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (filteredEntries.isEmpty) {
      final text = _entries.isEmpty ? '全局回收站为空' : '当前筛选条件下没有结果';
      return Center(
        child: Text(
          text,
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    return ListView.separated(
      itemCount: filteredEntries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _buildEntryCard(theme, filteredEntries[index]),
    );
  }

  Widget _buildEntryCard(ShadThemeData theme, _GlobalTrashEntry entry) {
    final busy = _busyEntries.contains(entry.id);
    final selected = _selectedIds.contains(entry.id);
    return ShadCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShadCheckbox(
                value: selected,
                enabled: !busy,
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          if (value) {
                            _selectedIds.add(entry.id);
                          } else {
                            _selectedIds.remove(entry.id);
                          }
                        });
                      },
              ),
              Icon(
                entry.item.isDir
                    ? LucideIcons.folderArchive
                    : LucideIcons.fileX2,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                entry.item.deletedAt,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('存储桶 ${entry.bucket}'),
              Text(entry.item.isDir ? '目录' : '文件'),
              Text(entry.item.sizeText),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.item.originalKey,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: busy ? null : () => unawaited(_restoreEntry(entry)),
                child: Text(busy ? '处理中...' : '恢复'),
              ),
              const SizedBox(width: 8),
              ShadButton.destructive(
                size: ShadButtonSize.sm,
                onPressed: busy ? null : () => unawaited(_deleteEntry(entry)),
                child: const Text('彻底删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlobalTrashEntry {
  const _GlobalTrashEntry({required this.bucket, required this.item});

  final String bucket;
  final TrashItem item;

  String get id => '$bucket:${item.id}';

  DateTime? get deletedAtDateTime =>
      DateTime.tryParse(item.deletedAt)?.toLocal();
}
