// 传输管理页：展示上传和下载任务列表及状态。
// 任务通过内存队列管理，刷新页面后清空。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';

/// 传输任务状态。
enum TransferStatus { pending, running, done, failed }

/// 单个传输任务。
class TransferTask {
  TransferTask({
    required this.type,
    required this.bucket,
    required this.key,
    required this.localPath,
    this.status = TransferStatus.pending,
    this.error,
  });

  final bool type; // true=upload, false=download
  final String bucket;
  final String key;
  final String localPath;
  TransferStatus status;
  String? error;

  String get displayName => key.split('/').last;
  String get typeLabel => type ? '上传' : '下载';
}

/// 全局传输队列，页面间共享。
class TransferQueue extends ChangeNotifier {
  final List<TransferTask> _tasks = [];

  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  void add(TransferTask task) {
    _tasks.insert(0, task);
    notifyListeners();
  }

  void update(int index, {TransferStatus? status, String? error}) {
    if (index < 0 || index >= _tasks.length) return;
    if (status != null) _tasks[index].status = status;
    if (error != null) _tasks[index].error = error;
    notifyListeners();
  }

  void clear() {
    _tasks.clear();
    notifyListeners();
  }
}

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key, required this.api, required this.config});

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题。
          Text(
            '传输管理',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '查看上传和下载任务的状态。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          // 任务列表。
          Expanded(child: _buildList(theme)),
        ],
      ),
    );
  }

  Widget _buildList(ShadThemeData theme) {
    // TransferQueue 由 FileManagerPage 写入，这里只读。
    // 用 AnimatedBuilder 监听变化 — 暂时展示空态提示。
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_vert,
            size: 48,
            color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无传输任务',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在文件管理页面中选择文件上传或下载。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
