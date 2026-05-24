// 文件管理页：桶列表 -> 对象列表，支持上传和下载。
// 使用 shadcn 色系与 Card 组件，风格与登录页统一。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:file_picker/file_picker.dart';

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key, required this.api, required this.config});

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  List<BucketInfo>? _buckets;
  String? _activeBucket;
  List<ObjectInfo>? _objects;
  String _prefix = '';
  List<String> _breadcrumbs = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBuckets();
  }

  // --- 数据加载 ---

  Future<void> _loadBuckets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buckets = await widget.api.listBuckets(widget.config);
      if (!mounted) return;
      setState(() {
        _buckets = buckets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadObjects(String bucket, String prefix) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final objects = await widget.api.listObjects(
        widget.config,
        bucket,
        prefix,
      );
      if (!mounted) return;
      setState(() {
        _activeBucket = bucket;
        _objects = objects;
        _prefix = prefix;
        _breadcrumbs = prefix.split('/').where((s) => s.isNotEmpty).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // --- 导航 ---

  void _navigateToBucket(String b) => _loadObjects(b, '');

  void _navigateToPrefix(String p) {
    if (_activeBucket != null) _loadObjects(_activeBucket!, p);
  }

  void _navigateUp() {
    if (_activeBucket == null) return;
    final parts = _prefix.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      setState(() {
        _activeBucket = null;
        _objects = null;
        _prefix = '';
        _breadcrumbs = [];
      });
      return;
    }
    parts.removeLast();
    _loadObjects(_activeBucket!, parts.map((p) => '$p/').join());
  }

  void _navigateBreadcrumb(int index) {
    if (_activeBucket == null) return;
    if (index < 0) {
      setState(() {
        _activeBucket = null;
        _objects = null;
        _prefix = '';
        _breadcrumbs = [];
      });
      return;
    }
    final segs = _breadcrumbs.sublist(0, index + 1);
    _loadObjects(_activeBucket!, segs.map((s) => '$s/').join());
  }

  // --- 上传 & 下载 ---

  Future<void> _upload() async {
    if (_activeBucket == null) return;
    final result = await FilePicker.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final key = _prefix + file.name;
    setState(() => _loading = true);
    try {
      await widget.api.uploadFile(
        widget.config,
        _activeBucket!,
        key,
        file.path!,
      );
      if (!mounted) return;
      await _loadObjects(_activeBucket!, _prefix);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _download(ObjectInfo obj) async {
    if (_activeBucket == null) return;
    final savePath = await FilePicker.saveFile(
      dialogTitle: '下载到',
      fileName: obj.displayName,
    );
    if (savePath == null) return;

    setState(() => _loading = true);
    try {
      await widget.api.downloadFile(
        widget.config,
        _activeBucket!,
        obj.key,
        savePath,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 32, right: 32, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          Expanded(child: _buildContent(theme)),
        ],
      ),
    );
  }

  Widget _buildHeader(ShadThemeData theme) {
    return Row(
      children: [
        Expanded(child: _buildBreadcrumbBar(theme)),
        if (_activeBucket != null) ...[
          ShadButton.outline(
            onPressed: _loading ? null : _upload,
            size: ShadButtonSize.sm,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.upload_file,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                const Text('上传'),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ShadButton.outline(
            onPressed: _loading ? null : _navigateUp,
            size: ShadButtonSize.sm,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                const Text('返回'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBreadcrumbBar(ShadThemeData theme) {
    if (_activeBucket == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文件管理',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '浏览和管理远程存储中的文件。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        GestureDetector(
          onTap: () => _navigateBreadcrumb(-1),
          child: Text(
            _activeBucket!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        for (int i = 0; i < _breadcrumbs.length; i++) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _navigateBreadcrumb(i),
            child: Text(
              _breadcrumbs[i],
              style: TextStyle(
                fontSize: 14,
                fontWeight: i == _breadcrumbs.length - 1
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: i == _breadcrumbs.length - 1
                    ? theme.colorScheme.foreground
                    : theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent(ShadThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.destructive,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ShadButton(
              onPressed: _activeBucket == null
                  ? _loadBuckets
                  : () => _loadObjects(_activeBucket!, _prefix),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_activeBucket == null) return _buildBucketList(theme);
    return _buildObjectList(theme);
  }

  Widget _buildBucketList(ShadThemeData theme) {
    if (_buckets == null) return const SizedBox();
    if (_buckets!.isEmpty) {
      return _empty(theme, Icons.inventory_2_outlined, '没有可用的存储桶');
    }
    return _card(
      theme,
      ListView.builder(
        itemCount: _buckets!.length,
        itemBuilder: (ctx, i) => FileListTile(
          icon: Icons.inventory_2_outlined,
          title: _buckets![i].name,
          subtitle: '存储桶',
          onTap: () => _navigateToBucket(_buckets![i].name),
        ),
      ),
    );
  }

  Widget _buildObjectList(ShadThemeData theme) {
    if (_objects == null) return const SizedBox();
    if (_objects!.isEmpty) {
      return _empty(theme, Icons.folder_open, '此目录为空');
    }
    return _card(
      theme,
      ListView.builder(
        itemCount: _objects!.length,
        itemBuilder: (ctx, i) {
          final obj = _objects![i];
          return FileListTile(
            icon: obj.isDir
                ? Icons.folder_outlined
                : _fileIcon(obj.displayName),
            iconColor: obj.isDir ? theme.colorScheme.primary : null,
            title: obj.displayName,
            subtitle: obj.isDir
                ? '文件夹'
                : '${obj.sizeText}  ${obj.lastModified}',
            onTap: obj.isDir
                ? () => _navigateToPrefix(obj.key)
                : () => _download(obj),
          );
        },
      ),
    );
  }

  Widget _card(ShadThemeData theme, Widget child) {
    return ShadCard(padding: const EdgeInsets.all(4), child: child);
  }

  Widget _empty(ShadThemeData theme, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 44,
            color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.movie_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return Icons.audio_file_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
        return Icons.archive_outlined;
      default:
        return Icons.description_outlined;
    }
  }
}
