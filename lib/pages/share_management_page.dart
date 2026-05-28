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
    await _runBusy(record.id, () async {
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
    await _runBusy(record.id, () async {
      await widget.api.deleteShare(widget.config, record.id);
      ShareRecordsNotifier.instance.markChanged();
      await _loadShares();
    });
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

  Future<void> _runBusy(String id, Future<void> Function() action) async {
    setState(() => _busyIds.add(id));
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
                      '分享管理',
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '集中管理已经创建的分享记录，链接内容在详情中查看。',
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ShadButton.outline(
                onPressed: _loading ? null : () => unawaited(_loadShares()),
                child: const Text('刷新'),
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
      onOpenRecord: (record) => unawaited(_showRecordDetails(record)),
      onCopyLink: (record) => unawaited(_copyLink(record)),
      onOpenLink: (record) => unawaited(_openLink(record)),
      onRefreshRecord: (record) => unawaited(_refreshRecord(record)),
      onDeleteRecord: (record) => unawaited(_deleteRecord(record)),
    );
  }
}
