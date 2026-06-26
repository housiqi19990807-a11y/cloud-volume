// 远程目录选择器：弹出文件管理式的桶/目录浏览器。
// 第一级显示桶列表，进入桶后显示目录树，支持创建目录和选择当前目录。
// 选择后返回 (bucket, prefix, profileName, config) 四元组。
import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'remote_directory_picker_actions.dart';

/// 远程目录选择结果。
class RemoteDirectoryResult {
  const RemoteDirectoryResult({
    required this.bucket,
    required this.prefix,
    required this.profileName,
    required this.config,
  });

  final String bucket;
  final String prefix;
  final String profileName;
  final RemoteStorageConfig config;
}

/// 弹出远程目录选择器，返回选中的桶+目录前缀。
Future<RemoteDirectoryResult?> showRemoteDirectoryPicker({
  required BuildContext context,
  required RemoteStorageGateway api,
  required List<FileManagerBucketEntry> buckets,
  RemoteDirectoryResult? initial,
}) {
  return showShadDialog<RemoteDirectoryResult>(
    context: context,
    builder: (_) => RemoteDirectoryPickerDialog(
      api: api,
      buckets: buckets,
      initial: initial,
    ),
  );
}

class RemoteDirectoryPickerDialog extends StatefulWidget {
  const RemoteDirectoryPickerDialog({
    super.key,
    required this.api,
    required this.buckets,
    this.initial,
  });

  final RemoteStorageGateway api;
  final List<FileManagerBucketEntry> buckets;
  final RemoteDirectoryResult? initial;

  @override
  State<RemoteDirectoryPickerDialog> createState() =>
      _RemoteDirectoryPickerDialogState();
}

class _RemoteDirectoryPickerDialogState
    extends State<RemoteDirectoryPickerDialog> {
  // null = 桶列表视图；非 null = 已进入该桶，浏览目录。
  FileManagerBucketEntry? _activeBucket;
  String _prefix = '';
  List<ObjectInfo> _objects = const [];
  bool _loading = false;
  String? _error;

  // 创建目录弹窗状态。
  bool _showCreateDir = false;
  final _dirNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 若有初始值，直接进入对应桶和目录。
    if (widget.initial != null) {
      final init = widget.initial!;
      _activeBucket = widget.buckets.firstWhere(
        (b) => b.bucket.name == init.bucket && b.profileName == init.profileName,
        orElse: () => widget.buckets.first,
      );
      _prefix = init.prefix;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadObjects());
    }
  }

  @override
  void dispose() {
    _dirNameController.dispose();
    super.dispose();
  }

  /// 供 actions part 文件触发重建。
  void markDirty(VoidCallback fn) => setState(fn);

  /// 面包屑路径段：桶名 + 当前目录层级。
  List<String> get _breadcrumbs {
    if (_activeBucket == null) return [];
    final parts = <String>[_activeBucket!.bucket.name];
    if (_prefix.isNotEmpty) {
      parts.addAll(_prefix.split('/').where((s) => s.isNotEmpty));
    }
    return parts;
  }

  void _enterBucket(FileManagerBucketEntry entry) {
    setState(() {
      _activeBucket = entry;
      _prefix = '';
      _objects = const [];
      _error = null;
    });
    _loadObjects();
  }

  void _openDirectory(ObjectInfo obj) {
    setState(() {
      _prefix = obj.key;
      _loading = true;
      _error = null;
    });
    _loadObjects();
  }

  void _navigateToBreadcrumb(int index) {
    if (index == 0) {
      // 回到桶根目录。
      setState(() {
        _prefix = '';
        _loading = true;
      });
    } else {
      final parts = _prefix.split('/').where((s) => s.isNotEmpty).toList();
      setState(() {
        _prefix = parts.take(index).join('/');
        if (_prefix.isNotEmpty) _prefix += '/';
        _loading = true;
      });
    }
    _loadObjects();
  }

  void _goBackToBuckets() {
    setState(() {
      _activeBucket = null;
      _prefix = '';
      _objects = const [];
      _error = null;
    });
  }

  void _confirm() {
    if (_activeBucket == null) return;
    Navigator.of(context).pop(RemoteDirectoryResult(
      bucket: _activeBucket!.bucket.name,
      prefix: _prefix,
      profileName: _activeBucket!.profileName,
      config: _activeBucket!.config,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: const Text('选择远端目录'),
      description: Text(
        _activeBucket == null
            ? '选择一个存储桶进入。'
            : '浏览目录后点击「选择当前目录」确认。',
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      child: SizedBox(
        width: double.infinity,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBreadcrumbBar(theme),
            const SizedBox(height: 12),
            Expanded(child: _buildContent(theme)),
            const SizedBox(height: 12),
            buildCreateDirInput(theme),
            _buildActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbBar(ShadThemeData theme) {
    if (_activeBucket == null) {
      return const SizedBox(height: 4);
    }
    final crumbs = _breadcrumbs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        ),
      child: Row(
        children: [
          for (int i = 0; i < crumbs.length; i++) ...[
            if (i > 0) ...[
              Icon(LucideIcons.chevronRight, size: 12, color: theme.colorScheme.mutedForeground),
              const SizedBox(width: 4),
            ],
            GestureDetector(
              onTap: () => _navigateToBreadcrumb(i),
              child: Text(
                crumbs[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.normal,
                  color: i == crumbs.length - 1
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(ShadThemeData theme) {
    if (_activeBucket == null) {
      return _buildBucketList(theme);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 32, color: theme.colorScheme.destructive),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground)),
          ],
        ),
      );
    }
    final dirs = _objects.where((o) => o.isDir).toList();
    if (dirs.isEmpty) {
      return Center(
        child: Text(
          '当前目录下没有子目录。',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    return ListView.builder(
      itemCount: dirs.length,
      itemBuilder: (context, i) => _dirTile(theme, dirs[i]),
    );
  }

  Widget _buildBucketList(ShadThemeData theme) {
    if (widget.buckets.isEmpty) {
      return Center(
        child: Text(
          '没有可用的存储桶。',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    return ListView.builder(
      itemCount: widget.buckets.length,
      itemBuilder: (context, i) {
        final entry = widget.buckets[i];
        return _bucketTile(theme, entry);
      },
    );
  }

  Widget _bucketTile(ShadThemeData theme, FileManagerBucketEntry entry) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _enterBucket(entry),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
            ),
        child: Row(
          children: [
            const WhiteSurFileIcon(
              assetPath: 'assets/icons/whitesur/places/network-server-balanced.svg',
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.bucket.name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.foreground),
                  ),
                  Text(
                    entry.sourceLabel,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.mutedForeground),
          ],
        ),
      ),
    );
  }

  Widget _dirTile(ShadThemeData theme, ObjectInfo obj) {
    final name = obj.key.split('/').where((s) => s.isNotEmpty).last;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDirectory(obj),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
            ),
        child: Row(
          children: [
            Icon(LucideIcons.folder, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.foreground),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.mutedForeground),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ShadThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 左侧：返回桶列表 / 创建目录。
        Row(
          children: [
            if (_activeBucket != null)
              ShadButton.outline(
                onPressed: _goBackToBuckets,
                child: const Row(
                  children: [
                    Icon(LucideIcons.chevronLeft, size: 14),
                    SizedBox(width: 2),
                    Text('桶列表'),
                  ],
                ),
              ),
            if (_activeBucket != null) ...[
              const SizedBox(width: 8),
              ShadButton.outline(
                onPressed: _toggleCreateDir,
                child: const Row(
                  children: [
                    Icon(LucideIcons.folderPlus, size: 14),
                    SizedBox(width: 2),
                    Text('新建目录'),
                  ],
                ),
              ),
            ],
          ],
        ),
        // 右侧：取消 / 选择当前目录。
        Row(
          children: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            ShadButton(
              onPressed: _activeBucket == null ? null : _confirm,
              child: const Text('选择当前目录'),
            ),
          ],
        ),
      ],
    );
  }

  void _toggleCreateDir() {
    setState(() {
      _showCreateDir = !_showCreateDir;
      _dirNameController.clear();
    });
  }
}
