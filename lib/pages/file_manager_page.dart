// 文件管理页：负责面包屑导航、桶/对象浏览，以及上传下载交互。

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/utils/object_visibility.dart';
import 'package:remote_storage/widgets/create_directory_dialog.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key, required this.api, required this.config});

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  static const double _gridIconSize = 68;
  static const double _listIconSize = 20;
  static const double _bucketGridIconSize = 72;

  List<BucketInfo>? _buckets;
  String? _activeBucket;
  List<ObjectInfo>? _objects;
  String _prefix = '';
  List<String> _breadcrumbs = [];
  bool _loading = false;
  String? _error;
  bool _isGrid = false;

  @override
  void initState() {
    super.initState();
    _loadBuckets();
  }

  Future<bool> _loadBuckets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buckets = await widget.api.listBuckets(widget.config);
      if (!mounted) return false;
      setState(() {
        _buckets = buckets;
        _activeBucket = null;
        _objects = null;
        _prefix = '';
        _breadcrumbs = [];
        _loading = false;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return false;
    }
  }

  Future<bool> _loadObjects(String bucket, String prefix) async {
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
      if (!mounted) return false;
      setState(() {
        _activeBucket = bucket;
        _objects = objects;
        _prefix = prefix;
        _breadcrumbs = prefix.split('/').where((s) => s.isNotEmpty).toList();
        _loading = false;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return false;
    }
  }

  Future<void> _navToBucket(String bucket) {
    return _loadObjects(bucket, '');
  }

  Future<void> _navToPrefix(String prefix) {
    if (_activeBucket == null) return Future.value();
    return _loadObjects(_activeBucket!, prefix);
  }

  Future<void> _navUp() {
    if (_activeBucket == null) return Future.value();
    final parts = _prefix.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return _loadBuckets();
    parts.removeLast();
    return _loadObjects(_activeBucket!, parts.map((part) => '$part/').join());
  }

  Future<void> _navCrumb(int index) {
    if (_activeBucket == null) return Future.value();
    if (index < 0) return _loadBuckets();
    return _loadObjects(
      _activeBucket!,
      _breadcrumbs.sublist(0, index + 1).map((segment) => '$segment/').join(),
    );
  }

  Future<void> _upload() async {
    if (_activeBucket == null) return;
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final bucket = _activeBucket!;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) {
        continue;
      }
      final key = _prefix + file.name;
      final task = TransferQueue.instance.startTask(
        isUpload: true,
        bucket: bucket,
        key: key,
        localPath: path,
      );
      unawaited(_runUploadTask(task, bucket));
    }
  }

  Future<void> _download(ObjectInfo obj) async {
    if (_activeBucket == null) return;
    final initialDirectory = await resolveDefaultDownloadDirectory(
      widget.config.defaultDownloadDirectory,
    );
    final savePath = await FilePicker.saveFile(
      dialogTitle: '下载到',
      fileName: obj.displayName,
      initialDirectory: initialDirectory,
    );
    if (savePath == null) return;
    final task = TransferQueue.instance.startTask(
      isUpload: false,
      bucket: _activeBucket!,
      key: obj.key,
      localPath: savePath,
    );
    unawaited(_runDownloadTask(task));
  }

  Future<void> _createDirectory() async {
    if (_activeBucket == null) return;
    final controller = TextEditingController();
    String? errorText;
    bool creating = false;

    await showShadDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return CreateDirectoryDialog(
              controller: controller,
              errorText: errorText,
              creating: creating,
              onCancel: () => Navigator.of(dialogContext).pop(),
              onCreate: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = '目录名称不能为空');
                  return;
                }
                setDialogState(() {
                  creating = true;
                  errorText = null;
                });
                try {
                  await widget.api.createDirectory(
                    widget.config,
                    _activeBucket!,
                    _prefix,
                    name,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _loadObjects(_activeBucket!, _prefix);
                } catch (e) {
                  setDialogState(() {
                    creating = false;
                    errorText = e.toString();
                  });
                }
              },
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _runUploadTask(TransferTask task, String bucket) async {
    try {
      await widget.api.uploadFile(
        widget.config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
      if (!mounted || _activeBucket != bucket) return;
      await _loadObjects(bucket, _prefix);
    } catch (e) {
      TransferQueue.instance.markTaskFailed(task.id, e);
    }
  }

  Future<void> _runDownloadTask(TransferTask task) async {
    try {
      await widget.api.downloadFile(
        widget.config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
    } catch (e) {
      TransferQueue.instance.markTaskFailed(task.id, e);
    }
  }

  Future<void> _showObjectActions(ObjectInfo object, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        PopupMenuItem<String>(value: 'delete', child: Text('删除')),
      ],
    );
    if (!mounted || selected == null || _activeBucket == null) return;
    try {
      if (selected == 'rename') {
        final newName = await showRenameObjectDialog(context, object);
        if (newName == null ||
            newName.isEmpty ||
            newName == object.displayName) {
          return;
        }
        await widget.api.renameObject(
          widget.config,
          _activeBucket!,
          object.key,
          object.isDir,
          newName,
        );
      } else if (selected == 'delete') {
        final confirmed = await showDeleteObjectDialog(context, object);
        if (!confirmed) return;
        await widget.api.deleteObject(
          widget.config,
          _activeBucket!,
          object.key,
          object.isDir,
        );
      }
      if (!mounted) return;
      await _loadObjects(_activeBucket!, _prefix);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: FileManagerBreadcrumbBar(
            theme: theme,
            activeBucket: _activeBucket,
            breadcrumbs: _breadcrumbs,
            onOpenBucketList: () => unawaited(_loadBuckets()),
            onOpenBucketRoot: () => unawaited(_navToBucket(_activeBucket!)),
            onOpenCrumb: (index) => unawaited(_navCrumb(index)),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: FileManagerActionBar(
              theme: theme,
              isGrid: _isGrid,
              onToggleView: () => setState(() => _isGrid = !_isGrid),
              onCreateDirectory: _activeBucket == null || _loading
                  ? null
                  : _createDirectory,
              onUpload: _activeBucket == null || _loading ? null : _upload,
            ),
          ),
        ),
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
              LucideIcons.circleAlert,
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
                  ? () => unawaited(_loadBuckets())
                  : () => unawaited(_loadObjects(_activeBucket!, _prefix)),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_activeBucket == null) return _buildBucketView(theme);
    return _buildObjectView(theme);
  }

  Widget _buildBucketView(ShadThemeData theme) {
    if (_buckets == null) return const SizedBox();
    if (_buckets!.isEmpty) {
      return _empty(theme, LucideIcons.database, '没有可用的存储桶');
    }
    if (_isGrid) {
      return _gridWrap(
        _buckets!
            .map(
              (b) => FileGridItem(
                leading: const WhiteSurFileIcon(
                  assetPath: 'assets/icons/whitesur/places/network-server.svg',
                  size: _bucketGridIconSize,
                ),
                title: b.name,
                subtitle: '存储桶',
                onTap: () => unawaited(_navToBucket(b.name)),
              ),
            )
            .toList(),
      );
    }
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: ListView.builder(
        itemCount: _buckets!.length,
        itemBuilder: (ctx, i) {
          final bucket = _buckets![i];
          return FileListTile(
            leading: const WhiteSurFileIcon(
              assetPath: 'assets/icons/whitesur/places/network-server.svg',
              size: _listIconSize,
            ),
            title: bucket.name,
            subtitle: '存储桶',
            onTap: () => unawaited(_navToBucket(bucket.name)),
            showDivider: i != _buckets!.length - 1,
          );
        },
      ),
    );
  }

  Widget _buildObjectView(ShadThemeData theme) {
    if (_objects == null) return const SizedBox();
    return FileManagerObjectBrowser(
      objects: filterVisibleObjects(
        _objects!,
        hideDotFiles: widget.config.hideDotFiles,
      ),
      prefix: _prefix,
      isGrid: _isGrid,
      gridIconSize: _gridIconSize,
      listIconSize: _listIconSize,
      onOpenDirectory: (prefix) => unawaited(_navToPrefix(prefix)),
      onDownload: (object) => unawaited(_download(object)),
      onNavigateUp: () => unawaited(_navUp()),
      onShowObjectActions: (object, position) =>
          unawaited(_showObjectActions(object, position)),
    );
  }

  Widget _gridWrap(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 118).floor().clamp(
          4,
          10,
        );
        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.92,
          children: children,
        );
      },
    );
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
}
