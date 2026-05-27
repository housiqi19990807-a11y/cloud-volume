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
import 'package:remote_storage/state/share_records_notifier.dart';
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
import 'package:remote_storage/widgets/share_dialogs.dart';
import 'package:path/path.dart' as path;
import 'package:shadcn_ui/shadcn_ui.dart';

part 'file_manager_page_actions.dart';
part 'file_manager_page_mount.dart';
part 'file_manager_page_selection.dart';
part 'file_manager_page_trash.dart';

// 文件管理页首页模式：既支持普通文件浏览，也支持侧边栏独立回收站入口。
enum FileManagerHomeView { files, trash }

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({
    super.key,
    required this.api,
    required this.config,
    this.homeView = FileManagerHomeView.files,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final FileManagerHomeView homeView;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  static const double _gridIconSize = 68;
  static const double _listIconSize = 20;
  static const double _bucketGridIconSize = 72;
  static const Duration _mountStatusRefreshInterval = Duration(seconds: 4);

  final TextEditingController _searchController = TextEditingController();
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
  String _searchText = '';
  final Map<String, BucketMountStatus> _bucketMountStatuses =
      <String, BucketMountStatus>{};
  final Set<String> _mountBusyBuckets = <String>{};
  final Set<String> _selectedObjectKeys = <String>{};
  final Set<String> _deletingObjectKeys = <String>{};
  Timer? _mountStatusRefreshTimer;
  bool _mountStatusRefreshInFlight = false;

  BucketMountStatus? get _activeMountStatus =>
      _activeBucket == null ? null : _bucketMountStatuses[_activeBucket!];

  bool get _activeMountBusy =>
      _activeBucket != null && _mountBusyBuckets.contains(_activeBucket!);

  bool get _isTrashHome => widget.homeView == FileManagerHomeView.trash;

  bool get _hasSearchQuery => _searchText.isNotEmpty;

  List<BucketInfo> get _filteredBuckets {
    final buckets = _buckets ?? const <BucketInfo>[];
    if (!_hasSearchQuery) return buckets;
    return buckets
        .where((bucket) => bucket.name.toLowerCase().contains(_searchText))
        .toList(growable: false);
  }

  List<ObjectInfo> get _filteredVisibleObjects {
    final visibleObjects = _visibleSelectableObjects;
    if (!_hasSearchQuery) return visibleObjects;
    return visibleObjects
        .where(
          (object) =>
              object.displayName.toLowerCase().contains(_searchText) ||
              object.key.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }

  List<TrashItem> get _filteredTrashItems {
    final items = _trashItems ?? const <TrashItem>[];
    if (!_hasSearchQuery) return items;
    return items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_searchText) ||
              item.originalKey.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
    _startMountStatusRefreshTimer();
    _loadBuckets();
  }

  @override
  void dispose() {
    _mountStatusRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
        _deletingObjectKeys.clear();
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
        final visibleKeys = objects.map((object) => object.key).toSet();
        _activeBucket = bucket;
        _objects = objects;
        _trashItems = null;
        _prefix = prefix;
        _breadcrumbs = prefix.split('/').where((s) => s.isNotEmpty).toList();
        _showTrash = false;
        _selectedObjectKeys.clear();
        _deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
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
    if (_isTrashHome) {
      return _openBucketTrash(bucket);
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isTrashHome) ...[
          Text(
            '回收站',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _showTrash ? '管理当前存储桶中的已删除对象。' : '选择一个存储桶进入它的回收站。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
        ],
        FileManagerBreadcrumbBar(
          theme: theme,
          activeBucket: _activeBucket,
          breadcrumbs: _breadcrumbs,
          onOpenBucketList: () => unawaited(_loadBuckets()),
          onOpenBucketRoot: () => unawaited(_navToBucket(_activeBucket!)),
          onOpenCrumb: (index) => unawaited(_navCrumb(index)),
        ),
        const SizedBox(height: 12),
        FileManagerActionBar(
          theme: theme,
          isGrid: _isGrid,
          searchController: _searchController,
          searchEnabled: !_loading,
          searchPlaceholder: _showTrash
              ? '搜索回收站名称或原路径'
              : _activeBucket == null
              ? '搜索存储桶'
              : '搜索文件或目录',
          selectedCount: _selectedObjectKeys.length,
          batchDownloadEnabled: _selectedObjects.any((object) => !object.isDir),
          showingTrash: _showTrash,
          mounted: _showTrash ? false : (_activeMountStatus?.mounted ?? false),
          mountBusy: _showTrash ? false : _activeMountBusy,
          onToggleView: () => setState(() => _isGrid = !_isGrid),
          trashCloseLabel: _isTrashHome ? '返回存储桶' : '返回文件',
          onOpenTrash:
              _isTrashHome || _activeBucket == null || _loading || _showTrash
              ? null
              : _openBucketTrash,
          onCloseTrash: _activeBucket == null || _loading || !_showTrash
              ? null
              : _closeBucketTrash,
          onMount:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  _activeMountBusy ||
                  (_activeMountStatus?.mounted ?? false)
              ? null
              : _mountBucket,
          onUnmount:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  _activeMountBusy ||
                  !(_activeMountStatus?.mounted ?? false)
              ? null
              : _unmountBucket,
          onOpenMount:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  _activeMountBusy ||
                  !(_activeMountStatus?.mounted ?? false)
              ? null
              : _openMountedBucket,
          onCreateDirectory: _showTrash || _activeBucket == null || _loading
              ? null
              : _createDirectory,
          onUpload: _showTrash || _activeBucket == null || _loading
              ? null
              : _upload,
          onBatchDownload: _loading ? null : _downloadSelectedObjects,
          onBatchDelete: _loading ? null : _deleteSelectedObjects,
          onClearSelection: _clearSelection,
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
    final buckets = _filteredBuckets;
    if (buckets.isEmpty) {
      return _empty(
        theme,
        LucideIcons.database,
        _hasSearchQuery ? '没有匹配的存储桶' : '没有可用的存储桶',
      );
    }
    return FileManagerBucketBrowser(
      buckets: buckets,
      isGrid: _isGrid,
      gridIconSize: _bucketGridIconSize,
      listIconSize: _listIconSize,
      onOpenBucket: (bucket) => unawaited(_navToBucket(bucket)),
      mountStatuses: _isTrashHome
          ? const <String, BucketMountStatus>{}
          : _bucketMountStatuses,
      busyBuckets: _isTrashHome ? const <String>{} : _mountBusyBuckets,
      showActionColumn: !_isTrashHome,
      onOpenTrashBucket: _isTrashHome
          ? null
          : (bucket) => unawaited(_openBucketTrash(bucket)),
      onMountBucket: _isTrashHome
          ? null
          : (bucket) => unawaited(_mountBucket(bucket)),
      onUnmountBucket: _isTrashHome
          ? null
          : (bucket) => unawaited(_unmountBucket(bucket)),
      onOpenMountedBucket: _isTrashHome
          ? null
          : (bucket) => unawaited(_openMountedBucket(bucket)),
    );
  }

  Widget _buildObjectView(ShadThemeData theme) {
    if (_objects == null) return const SizedBox();
    final visibleObjects = _filteredVisibleObjects;
    if (visibleObjects.isEmpty) {
      return _empty(
        theme,
        LucideIcons.folderSearch,
        _hasSearchQuery ? '当前搜索没有结果' : '此目录为空',
      );
    }
    return FileManagerObjectBrowser(
      objects: visibleObjects,
      prefix: _prefix,
      isGrid: _isGrid,
      selectedKeys: _selectedObjectKeys,
      deletingKeys: _deletingObjectKeys,
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
