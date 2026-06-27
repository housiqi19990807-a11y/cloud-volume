// Detached sync-editor window gives the configuration wizard a roomy sub-window
// instead of a cramped modal dialog. Loads its own bridge and bucket list.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/file_sync_profile_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

class SyncEditorWindowApp extends StatefulWidget {
  const SyncEditorWindowApp({super.key, required this.args});

  final SyncEditorWindowArgs args;

  @override
  State<SyncEditorWindowApp> createState() => _SyncEditorWindowAppState();
}

class _SyncEditorWindowAppState extends State<SyncEditorWindowApp> {
  RemoteStorageGateway? _api;
  List<FileManagerBucketEntry> _buckets = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrapApi();
  }

  Future<void> _bootstrapApi() async {
    try {
      final api = await defaultRemoteStorageApiFactory();
      SyncProfileNotifier.instance.bindApi(api);
      // Load profiles and their bucket lists.
      final args = widget.args;
      final entries = <FileManagerBucketEntry>[];
      for (final name in args.profileNames) {
        final config = await api.loadProfile(name);
        final buckets = await api.listBuckets(config);
        final sourceLabel = _sourceLabel(config);
        for (final bucket in buckets) {
          entries.add(FileManagerBucketEntry.fromBucketInfo(
            bucket: bucket,
            profileName: name,
            sourceLabel: sourceLabel,
            config: config,
          ));
        }
      }
      entries.sort((a, b) {
        final sc = a.sourceLabel.compareTo(b.sourceLabel);
        return sc != 0 ? sc : a.bucket.name.compareTo(b.bucket.name);
      });
      if (mounted) setState(() { _api = api; _buckets = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _sourceLabel(RemoteStorageConfig config) {
    final name = config.displayName.trim().isNotEmpty
        ? config.displayName.trim()
        : config.accessKeyId.trim();
    final label = name.isEmpty ? '账号' : name;
    return '$label · ${config.storageType.label}';
  }

  Future<bool> _onSave(SyncProfile profile) async {
    try {
      await SyncProfileNotifier.instance.saveProfile(profile);
      return true;
    } catch (e) {
      if (!mounted) return false;
      showAppErrorToast(context, message: '保存失败：$e');
      return false;
    }
  }

  @override
  void dispose() {
    SyncProfileNotifier.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isEdit = widget.args.initialProfile != null;
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Column(
        children: [
          _SyncEditorTitleBar(title: isEdit ? '编辑同步配置' : '新建同步配置'),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 40,
                color: ShadTheme.of(context).colorScheme.destructive),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
      child: FileSyncProfileEditor(
        api: _api!,
        buckets: _buckets,
        initial: widget.args.initialProfile,
        onSave: _onSave,
        onSaved: () {
          // 保存成功后关闭子窗口，不关闭主编排器。
          windowManager.close();
        },
      ),
    );
  }
}

class _SyncEditorTitleBar extends StatelessWidget {
  const _SyncEditorTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return DragToMoveArea(
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => windowManager.close(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
