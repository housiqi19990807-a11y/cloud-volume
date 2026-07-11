// Account editor sub-window built on the shared DesktopModalSubWindowApp.
// Owns only the bridge bootstrap, save logic, and Baidu OAuth callbacks —
// the title bar, scrim, lifecycle, loading/error states, and close sequence
// are handled by the generic shell.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/account_editor_window_args.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/account_profile_name.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/app/desktop_modal_sub_window_app.dart';

class AccountEditorWindowApp extends StatelessWidget {
  const AccountEditorWindowApp({super.key, required this.args});

  final AccountEditorWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return DesktopModalSubWindowApp<RemoteStorageGateway>(
      title: args.editing ? '编辑账号' : '新增账号',
      creatorWindowId: args.creatorWindowId,
      bootstrap: () async {
        DesktopWindowMethodHost.ensureInstalled();
        return defaultRemoteStorageApiFactory();
      },
      contentBuilder: (context, api) => _AccountEditorContent(
        api: api,
        args: args,
      ),
    );
  }
}

/// Holds the save + Baidu OAuth callbacks that [CloudStorageAccountDialog]
/// needs. Lives inside the generic shell's scroll view.
class _AccountEditorContent extends StatefulWidget {
  const _AccountEditorContent({required this.api, required this.args});

  final RemoteStorageGateway api;
  final AccountEditorWindowArgs args;

  @override
  State<_AccountEditorContent> createState() => _AccountEditorContentState();
}

class _AccountEditorContentState extends State<_AccountEditorContent> {
  @override
  void initState() {
    super.initState();
    // Register the saved-callback so the parent window refreshes after save.
    DesktopWindowMethodHost.registerAccountEditorSavedCallback(
      widget.args.creatorWindowId,
      () {},
    );
  }

  Future<String> _startBaiduPanAuthorization() async {
    return widget.api.startBaiduPanAuthorization();
  }

  Future<RemoteStorageConfig> _authorizeBaiduPan(
    String displayName,
    String code,
  ) async {
    return widget.api.authorizeBaiduPan(displayName, code);
  }

  Future<bool> _onSave(RemoteStorageConfig config) async {
    try {
      final profileName = widget.args.profileName ??
          generateAccountProfileName(config.displayName, config.storageType);
      await widget.api.saveProfile(profileName, config);
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
    return CloudStorageAccountDialog(
      initialConfig: widget.args.initialConfig,
      editing: widget.args.editing,
      asDialog: false,
      onSave: _onSave,
      onSaved: _onSaved,
      onCancel: () {},
      onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
      onAuthorizeBaiduPan: _authorizeBaiduPan,
    );
  }
}
