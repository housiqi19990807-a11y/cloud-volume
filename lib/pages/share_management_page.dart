// 分享管理页：展示本地分享记录，并通过详情弹窗管理链接。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/share_records_notifier.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/page_header_actions.dart';
import 'package:remote_storage/widgets/share_dialogs.dart';
import 'package:remote_storage/widgets/share_management_browser.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ShareManagementPage extends StatefulWidget {
  const ShareManagementPage({
    super.key,
    required this.api,
    required this.config,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

  @override
  State<ShareManagementPage> createState() => _ShareManagementPageState();
}

class _ShareManagementPageState extends State<ShareManagementPage> {
  static const Duration _tickerInterval = Duration(seconds: 30);

  List<ShareRecord> _records = const <ShareRecord>[];
  final Set<String> _busyIds = <String>{};
  final Set<String> _selectedIds = <String>{};
  Timer? _ticker;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ShareRecordsNotifier.instance.addListener(_reloadFromNotifier);
    _ticker = Timer.periodic(
      _tickerInterval,
      (_) => mounted ? setState(() {}) : null,
    );
    unawaited(_loadShares());
  }

  @override
  void didUpdateWidget(covariant ShareManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      unawaited(_loadShares());
    }
  }

  @override
  void dispose() {
    ShareRecordsNotifier.instance.removeListener(_reloadFromNotifier);
    _ticker?.cancel();
    super.dispose();
  }

  void _reloadFromNotifier() {
    unawaited(_loadShares());
  }

  ShareRecord? _recordById(String id) {
    for (final record in _records) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  void _toggleSelection(ShareRecord record) {
    setState(() {
      if (_selectedIds.contains(record.id)) {
        _selectedIds.remove(record.id);
      } else {
        _selectedIds.add(record.id);
      }
    });
  }

  void _toggleSelectAll() {
    final selectableIds = _records
        .where((record) => !_busyIds.contains(record.id))
        .map((record) => record.id)
        .toList(growable: false);
    final allSelected =
        selectableIds.isNotEmpty && selectableIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(selectableIds);
      } else {
        _selectedIds.addAll(selectableIds);
      }
    });
  }

  Future<void> _loadShares() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await widget.api.listShares(widget.config);
      if (!mounted) {
        return;
      }
      setState(() {
        _records = records;
        _selectedIds.removeWhere(
          (id) => !records.any((record) => record.id == id),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _copyLink(ShareRecord record) async {
    await Clipboard.setData(ClipboardData(text: record.url));
    if (!mounted) {
      return;
    }
    showAppToast(context, message: '分享链接已复制');
  }

  Future<void> _openLink(ShareRecord record) async {
    try {
      await openShareUrl(record.url);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppErrorToast(context, message: error.toString());
    }
  }

  Future<void> _refreshRecord(ShareRecord record) async {
    final durationSec = await showShareDurationDialog(
      context,
      title: '更新有效时间',
      description: '更新后会重新生成一个预签名下载链接。',
      confirmLabel: '更新链接',
      initialHours: (record.durationSec / 3600).round().clamp(1, 168),
    );
    if (durationSec == null) {
      return;
    }
    await _runBusy(<String>[record.id], () async {
      await widget.api.refreshShare(widget.config, record.id, durationSec);
      ShareRecordsNotifier.instance.markChanged();
      await _loadShares();
    });
  }

  Future<void> _deleteRecord(ShareRecord record) async {
    final confirmed = await showDeleteShareRecordDialog(context, record);
    if (!confirmed) {
      return;
    }
    await _runBusy(<String>[record.id], () async {
      await widget.api.deleteShare(widget.config, record.id);
      ShareRecordsNotifier.instance.markChanged();
      await _loadShares();
    });
  }

  Future<void> _deleteSelected() async {
    final targets = _records
        .where((record) => _selectedIds.contains(record.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    final confirmed = await showDeleteShareRecordsDialog(
      context,
      targets.length,
    );
    if (!confirmed) {
      return;
    }
    await _runBusy(
      targets.map((record) => record.id).toList(growable: false),
      () async {
        for (final record in targets) {
          await widget.api.deleteShare(widget.config, record.id);
        }
        ShareRecordsNotifier.instance.markChanged();
        await _loadShares();
        if (!mounted) {
          return;
        }
        showAppToast(context, message: '已删除 ${targets.length} 条分享记录');
      },
    );
  }

  Future<void> _showRecordDetails(ShareRecord record) async {
    final latest = _recordById(record.id) ?? record;
    final action = await showShareRecordDetailsDialog(
      context,
      record: latest,
      busy: _busyIds.contains(latest.id),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ShareRecordDetailAction.copyLink:
        await _copyLink(latest);
        return;
      case ShareRecordDetailAction.openLink:
        await _openLink(latest);
        return;
      case ShareRecordDetailAction.refresh:
        await _refreshRecord(latest);
        return;
      case ShareRecordDetailAction.delete:
        await _deleteRecord(latest);
        return;
    }
  }

  Future<void> _runBusy(
    List<String> ids,
    Future<void> Function() action,
  ) async {
    setState(() {
      _busyIds.addAll(ids);
      _selectedIds.removeAll(ids);
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() => _busyIds.removeAll(ids));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final selectedCount = _selectedIds.length;
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                fit: FlexFit.tight,
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分享管理',
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '集中管理已经创建的分享记录，链接内容在详情中查看。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (selectedCount > 0)
                PageHeaderActions(
                  primary: [
                    Text(
                      '已选 $selectedCount 项',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    ShadButton.destructive(
                      onPressed: _loading
                          ? null
                          : () => unawaited(_deleteSelected()),
                      child: const Text('删除选中'),
                    ),
                  ],
                  secondary: [
                    SecondaryAction(
                      label: '取消选择',
                      onPressed: () => setState(() => _selectedIds.clear()),
                      builder: (_) => ShadButton.outline(
                        onPressed: () =>
                            setState(() => _selectedIds.clear()),
                        child: const Text('取消选择'),
                      ),
                    ),
                  ],
                )
              else
                PageHeaderActions(
                  primary: [
                    ShadButton.outline(
                      onPressed: _loading
                          ? null
                          : () => unawaited(_loadShares()),
                      child: const Text('刷新'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ShadThemeData theme) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
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
    if (_records.isEmpty) {
      return Center(
        child: Text(
          '还没有分享记录',
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    return ShareManagementBrowser(
      records: _records,
      busyIds: _busyIds,
      selectedIds: _selectedIds,
      onOpenRecord: (record) => unawaited(_showRecordDetails(record)),
      onCopyLink: (record) => unawaited(_copyLink(record)),
      onOpenLink: (record) => unawaited(_openLink(record)),
      onRefreshRecord: (record) => unawaited(_refreshRecord(record)),
      onDeleteRecord: (record) => unawaited(_deleteRecord(record)),
      onToggleSelection: _toggleSelection,
      onToggleSelectAll: _toggleSelectAll,
    );
  }
}
