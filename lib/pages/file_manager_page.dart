// 文件管理页：负责面包屑导航、桶/对象浏览，以及上传下载交互。

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/services/file_access_service.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/utils/object_visibility.dart';
import 'package:remote_storage/widgets/create_directory_dialog.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';
import 'package:remote_storage/widgets/file_manager_bucket_browser.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/file_manager_trash_browser.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:path/path.dart' as path;
import 'package:shadcn_ui/shadcn_ui.dart';

part 'file_manager_page_actions.dart';
part 'file_manager_page_mount.dart';
part 'file_manager_page_selection.dart';
part 'file_manager_page_trash.dart';

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
  static const Duration _mountStatusRefreshInterval = Duration(seconds: 4);

  List<BucketInfo>? _buckets;
  String? _activeBucket;
  List<ObjectInfo>? _objects;
  List<TrashItem>? _trashItems;
  String _prefix = '';
  List<String> _breadcrumbs = [];
  bool _loading = false;
  String? _error;
  bool _isGrid = false;
  bool _showTrash = false;
  final Map<String, BucketMountStatus> _bucketMountStatuses =
      <String, BucketMountStatus>{};
  final Set<String> _mountBusyBuckets = <String>{};
  final Set<String> _selectedObjectKeys = <String>{};
  Timer? _mountStatusRefreshTimer;
  bool _mountStatusRefreshInFlight = false;

  BucketMountStatus? get _activeMountStatus =>
      _activeBucket == null ? null : _bucketMountStatuses[_activeBucket!];

  bool get _activeMountBusy =>
      _activeBucket != null && _mountBusyBuckets.contains(_activeBucket!);

  @override
  void initState() {
    super.initState();
    _startMountStatusRefreshTimer();
    _loadBuckets();
  }

  @override
  void dispose() {
    _mountStatusRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.fileOpenMode != widget.config.fileOpenMode) {
      _clearSelection();
    }
    if (oldWidget.config != widget.config) {
      unawaited(_refreshVisibleMountStatuses());
    }
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
        _trashItems = null;
        _prefix = '';
        _breadcrumbs = [];
        _showTrash = false;
        _bucketMountStatuses.clear();
        _mountBusyBuckets.clear();
        _selectedObjectKeys.clear();
        _loading = false;
      });
      unawaited(_refreshBucketMountStatuses(buckets));
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
        _trashItems = null;
        _prefix = prefix;
        _breadcrumbs = prefix.split('/').where((s) => s.isNotEmpty).toList();
        _showTrash = false;
        _selectedObjectKeys.clear();
        _loading = false;
      });
      unawaited(_refreshMountStatus(bucket));
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

  void _startMountStatusRefreshTimer() {
    _mountStatusRefreshTimer?.cancel();
    _mountStatusRefreshTimer = Timer.periodic(
      _mountStatusRefreshInterval,
      (_) => unawaited(_refreshVisibleMountStatuses()),
    );
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
        Align(
          alignment: Alignment.centerRight,
          child: FileManagerActionBar(
            theme: theme,
            isGrid: _isGrid,
            selectedCount: _selectedObjectKeys.length,
            batchDownloadEnabled: _selectedObjects.any(
              (object) => !object.isDir,
            ),
            showingTrash: _showTrash,
            mounted: _activeMountStatus?.mounted ?? false,
            mountBusy: _activeMountBusy,
            onToggleView: () => setState(() => _isGrid = !_isGrid),
            onOpenTrash: _activeBucket == null || _loading || _showTrash
                ? null
                : _openBucketTrash,
            onCloseTrash: _activeBucket == null || _loading || !_showTrash
                ? null
                : _closeBucketTrash,
            onMount:
                _activeBucket == null ||
                    _loading ||
                    _activeMountBusy ||
                    (_activeMountStatus?.mounted ?? false)
                ? null
                : _mountBucket,
            onUnmount:
                _activeBucket == null ||
                    _loading ||
                    _activeMountBusy ||
                    !(_activeMountStatus?.mounted ?? false)
                ? null
                : _unmountBucket,
            onOpenMount:
                _activeBucket == null ||
                    _loading ||
                    _activeMountBusy ||
                    !(_activeMountStatus?.mounted ?? false)
                ? null
                : _openMountedBucket,
            onCreateDirectory: _activeBucket == null || _loading
                ? null
                : _createDirectory,
            onUpload: _activeBucket == null || _loading ? null : _upload,
            onBatchDownload: _loading ? null : _downloadSelectedObjects,
            onBatchDelete: _loading ? null : _deleteSelectedObjects,
            onClearSelection: _clearSelection,
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
    if (_showTrash) return _buildTrashView(theme);
    return _buildObjectView(theme);
  }

  Widget _buildBucketView(ShadThemeData theme) {
    if (_buckets == null) return const SizedBox();
    if (_buckets!.isEmpty) {
      return _empty(theme, LucideIcons.database, '没有可用的存储桶');
    }
    return FileManagerBucketBrowser(
      buckets: _buckets!,
      isGrid: _isGrid,
      gridIconSize: _bucketGridIconSize,
      listIconSize: _listIconSize,
      onOpenBucket: (bucket) => unawaited(_navToBucket(bucket)),
      mountStatuses: _bucketMountStatuses,
      busyBuckets: _mountBusyBuckets,
      onOpenTrashBucket: (bucket) => unawaited(_openBucketTrash(bucket)),
      onMountBucket: (bucket) => unawaited(_mountBucket(bucket)),
      onUnmountBucket: (bucket) => unawaited(_unmountBucket(bucket)),
      onOpenMountedBucket: (bucket) => unawaited(_openMountedBucket(bucket)),
    );
  }

  Widget _buildObjectView(ShadThemeData theme) {
    if (_objects == null) return const SizedBox();
    final visibleObjects = _visibleSelectableObjects;
    return FileManagerObjectBrowser(
      objects: visibleObjects,
      prefix: _prefix,
      isGrid: _isGrid,
      fileOpenMode: widget.config.fileOpenMode,
      selectedKeys: _selectedObjectKeys,
      gridIconSize: _gridIconSize,
      listIconSize: _listIconSize,
      onOpenDirectory: (prefix) => unawaited(_navToPrefix(prefix)),
      onOpenFile: (object) => unawaited(_openObject(object)),
      onDownloadFile: (object) => unawaited(_downloadObject(object)),
      onNavigateUp: () => unawaited(_navUp()),
      onToggleSelection: _toggleObjectSelection,
      onToggleSelectAll: _toggleSelectAllObjects,
      onObjectAction: (object, action) =>
          unawaited(_handleObjectAction(object, action)),
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
