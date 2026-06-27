// Detached sync-editor window gives the configuration wizard a roomy sub-window
// instead of a cramped modal dialog. Loads its own bridge and bucket list.
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/file_sync_profile_editor.dart';
import 'package:remote_storage/widgets/desktop_modal_parent_focus_relay.dart';
import 'package:remote_storage/widgets/desktop_modal_window_focus_gate.dart';
import 'package:remote_storage/widgets/desktop_modal_scrim.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

/// 子窗口根 widget：提供 ShadApp + 主题，内部放置状态化的编辑器页面。
class SyncEditorWindowApp extends StatelessWidget {
  const SyncEditorWindowApp({super.key, required this.args});

  final SyncEditorWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return DesktopModalParentFocusRelay(
      child: ShadApp(
      title: '云卷 - 同步配置',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(AccentPreset.blue),
      home: DesktopModalWindowFocusGate(child: Stack(children: [_SyncEditorBody(args: args), const DesktopModalScrim()])),
    ),
    );
  }
}

class _SyncEditorBody extends StatefulWidget {
  const _SyncEditorBody({required this.args});

  final SyncEditorWindowArgs args;

  @override
  State<_SyncEditorBody> createState() => _SyncEditorBodyState();
}

Future<void> _closeSyncEditorWindow(String creatorWindowId) async {
  final id = (await WindowController.fromCurrentEngine()).windowId;
  DesktopModalOverlayController.instance.unregisterChildWindow(id);
  await notifyCreatorModalOverlayRelease(creatorWindowId);
  await clearModalChildWindowChrome();
  await windowManager.close();
}

class _SyncEditorBodyState extends State<_SyncEditorBody> {
  RemoteStorageGateway? _api;
  List<FileManagerBucketEntry> _buckets = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    DesktopWindowMethodHost.ensureInstalled();
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
      if (mounted) {
        setState(() {
          _api = api;
          _buckets = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
          _SyncEditorTitleBar(
            title: isEdit ? '编辑同步配置' : '新建同步配置',
            creatorWindowId: widget.args.creatorWindowId,
          ),
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
            Icon(LucideIcons.alertCircle, size: 40,
                color: theme.colorScheme.destructive),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
      child: FileSyncProfileEditor(
        api: _api!,
        buckets: _buckets,
        initial: widget.args.initialProfile,
        onSave: _onSave,
        onSaved: () => _closeSyncEditorWindow(widget.args.creatorWindowId),
        asDialog: false,
        creatorWindowId: widget.args.creatorWindowId,
        anchorFrameLeft: widget.args.creatorFrameLeft,
        anchorFrameTop: widget.args.creatorFrameTop,
        anchorFrameWidth: widget.args.creatorFrameWidth,
        anchorFrameHeight: widget.args.creatorFrameHeight,
      ),
    );
  }
}

class _SyncEditorTitleBar extends StatelessWidget {
  const _SyncEditorTitleBar({
    required this.title,
    required this.creatorWindowId,
  });

  final String title;
  final String creatorWindowId;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
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
            onPressed: () => _closeSyncEditorWindow(creatorWindowId),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class SyncEditorWindowLifecycle extends StatefulWidget {
  const SyncEditorWindowLifecycle({
    super.key,
    required this.creatorWindowId,
    required this.child,
  });

  final String creatorWindowId;
  final Widget child;

  @override
  State<SyncEditorWindowLifecycle> createState() =>
      _SyncEditorWindowLifecycleState();
}

class _SyncEditorWindowLifecycleState extends State<SyncEditorWindowLifecycle>
    with WindowListener {
  var _released = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _releaseParentOverlayOnce();
    super.dispose();
  }

  @override
  void onWindowClose() {
    _releaseParentOverlayOnce();
  }

  Future<void> _releaseParentOverlayOnce() async {
    if (_released) return;
    _released = true;
    final id = (await WindowController.fromCurrentEngine()).windowId;
    DesktopModalOverlayController.instance.unregisterChildWindow(id);
    await notifyCreatorModalOverlayRelease(widget.creatorWindowId);
    await clearModalChildWindowChrome();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
