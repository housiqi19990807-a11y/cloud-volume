// 分享管理页：展示本地分享记录，并支持复制、续期和删除。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/share_records_notifier.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/share_dialogs.dart';
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
                      '管理已经创建的预签名分享链接，可复制、续期或删除记录。',
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
      return const Center(child: CircularProgressIndicator());
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
    return ListView.separated(
      itemCount: _records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildRecordCard(theme, _records[index]),
    );
  }

  Widget _buildRecordCard(ShadThemeData theme, ShareRecord record) {
    final busy = _busyIds.contains(record.id);
    return ShadCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                _remainingText(record),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _isExpired(record)
                      ? theme.colorScheme.destructive
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${record.bucket} / ${record.key}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(record.url, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('有效至 ${_formatDateTime(record.expiresAtDateTime)}'),
              Text('时长 ${_formatDuration(record.durationSec)}'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: busy ? null : () => unawaited(_copyLink(record)),
                child: const Text('复制链接'),
              ),
              const SizedBox(width: 8),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: busy ? null : () => unawaited(_openLink(record)),
                child: const Text('打开链接'),
              ),
              const SizedBox(width: 8),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: busy
                    ? null
                    : () => unawaited(_refreshRecord(record)),
                child: Text(busy ? '处理中...' : '更新有效时间'),
              ),
              const SizedBox(width: 8),
              ShadButton.destructive(
                size: ShadButtonSize.sm,
                onPressed: busy ? null : () => unawaited(_deleteRecord(record)),
                child: const Text('删除记录'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isExpired(ShareRecord record) {
    final expiresAt = record.expiresAtDateTime;
    return expiresAt == null || !expiresAt.isAfter(DateTime.now());
  }

  String _remainingText(ShareRecord record) {
    final expiresAt = record.expiresAtDateTime;
    if (expiresAt == null) {
      return '有效期未知';
    }
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return '已过期';
    }
    if (remaining.inDays >= 1) {
      return '剩余 ${remaining.inDays} 天';
    }
    if (remaining.inHours >= 1) {
      return '剩余 ${remaining.inHours} 小时';
    }
    if (remaining.inMinutes >= 1) {
      return '剩余 ${remaining.inMinutes} 分钟';
    }
    return '即将过期';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '--';
    }
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatDuration(int durationSec) {
    final hours = durationSec ~/ 3600;
    if (hours % 24 == 0) {
      return '${hours ~/ 24} 天';
    }
    return '$hours 小时';
  }
}
