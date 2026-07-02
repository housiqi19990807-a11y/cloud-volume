// Detached account editor window gives the add/edit form a roomy sub-window
// instead of a cramped modal dialog. Loads its own bridge and saves the profile
// directly, then notifies the parent window to refresh its list.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/account_editor_window_args.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/utils/account_profile_name.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/desktop_modal_parent_focus_relay.dart';
import 'package:remote_storage/widgets/desktop_modal_window_focus_gate.dart';
import 'package:remote_storage/widgets/desktop_modal_scrim.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

/// 子窗口根 widget：提供 ShadApp + 主题，内部放置状态化的编辑器页面。
class AccountEditorWindowApp extends StatelessWidget {
  const AccountEditorWindowApp({super.key, required this.args});

  final AccountEditorWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: '云卷 - 账号管理',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(AccentPreset.blue),
      home: AccountEditorWindowLifecycle(
        creatorWindowId: args.creatorWindowId,
        child: DesktopModalParentFocusRelay(
          child: DesktopModalWindowFocusGate(
            child: Stack(
              children: [
                _AccountEditorBody(args: args),
                const DesktopModalScrim(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountEditorBody extends StatefulWidget {
  const _AccountEditorBody({required this.args});

  final AccountEditorWindowArgs args;

  @override
  State<_AccountEditorBody> createState() => _AccountEditorBodyState();
}

Future<void> _closeAccountEditorWindow(String creatorWindowId) async {
  final id = (await WindowController.fromCurrentEngine()).windowId;
  DesktopModalOverlayController.instance.unregisterChildWindow(id);
  await notifyCreatorModalOverlayRelease(creatorWindowId);
  await clearModalChildWindowChrome();
  await windowManager.close();
}

class _AccountEditorBodyState extends State<_AccountEditorBody> {
  RemoteStorageGateway? _api;
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
      if (mounted) {
        setState(() {
          _api = api;
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

  Future<String> _startBaiduPanAuthorization() async {
    return _api!.startBaiduPanAuthorization();
  }

  Future<RemoteStorageConfig> _authorizeBaiduPan(
    String displayName,
    String code,
  ) async {
    return _api!.authorizeBaiduPan(displayName, code);
  }

  Future<bool> _onSave(RemoteStorageConfig config) async {
    try {
      final profileName = widget.args.profileName ??
          generateAccountProfileName(config.displayName, config.storageType);
      await _api!.saveProfile(profileName, config);
      if (!mounted) return false;
      showAppToast(
        context,
        title: widget.args.editing ? '账号已更新' : '账号已保存',
        message: config.displayName,
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      showAppErrorToast(context, message: '保存失败：$e');
      return false;
    }
  }

  Future<void> _onSaved() async {
    await _notifyParentSaved();
    await _closeAccountEditorWindow(widget.args.creatorWindowId);
  }

  Future<void> _notifyParentSaved() async {
    final targetId = widget.args.creatorWindowId;
    final controllers = await WindowController.getAll();
    for (final c in controllers) {
      if (c.windowId == targetId) {
        await c.invokeMethod('account_editor_saved', {
          'creatorWindowId': targetId,
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Column(
        children: [
          _AccountEditorTitleBar(
            title: widget.args.editing ? '编辑账号' : '新增账号',
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: SingleChildScrollView(
        child: CloudStorageAccountDialog(
          initialConfig: widget.args.initialConfig,
          editing: widget.args.editing,
          asDialog: false,
          onSave: _onSave,
          onSaved: _onSaved,
          onCancel: () => _closeAccountEditorWindow(widget.args.creatorWindowId),
          onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
          onAuthorizeBaiduPan: _authorizeBaiduPan,
        ),
      ),
    );
  }
}

class _AccountEditorTitleBar extends StatelessWidget {
  const _AccountEditorTitleBar({
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
            onPressed: () => _closeAccountEditorWindow(creatorWindowId),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class AccountEditorWindowLifecycle extends StatefulWidget {
  const AccountEditorWindowLifecycle({
    super.key,
    required this.creatorWindowId,
    required this.child,
  });

  final String creatorWindowId;
  final Widget child;

  @override
  State<AccountEditorWindowLifecycle> createState() =>
      _AccountEditorWindowLifecycleState();
}

class _AccountEditorWindowLifecycleState
    extends State<AccountEditorWindowLifecycle>
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
