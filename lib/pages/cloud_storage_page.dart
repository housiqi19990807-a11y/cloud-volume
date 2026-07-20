// 账号管理页负责展示所有账号，并把账号新增、编辑与退出操作串起来。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/account_editor_presenter.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/account_profile_name.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_list.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStoragePage extends StatefulWidget {
  const CloudStoragePage({
    super.key,
    required this.state,
    required this.api,
    required this.onRefresh,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onRefresh;

  @override
  State<CloudStoragePage> createState() => _CloudStoragePageState();
}

class _CloudStoragePageState extends State<CloudStoragePage> {
  bool _isGrid = false;
  bool _busy = false;
  late List<ProfileInfo> _accounts;

  @override
  void initState() {
    super.initState();
    _accounts = List<ProfileInfo>.from(widget.state.profiles);
  }

  @override
  void didUpdateWidget(covariant CloudStoragePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state.profiles, widget.state.profiles) ||
        oldWidget.state.profiles != widget.state.profiles) {
      _accounts = List<ProfileInfo>.from(widget.state.profiles);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(theme: theme, onAddAccount: _showAddAccountDialog),
          const SizedBox(height: 14),
          FileManagerActionBar(
            theme: theme,
            isGrid: _isGrid,
            searchEnabled: !_busy,
            onToggleView: () => setState(() => _isGrid = !_isGrid),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CloudStorageAccountList(
              accounts: _accounts,
              isGrid: _isGrid,
              busy: _busy,
              onEdit: _showEditAccountDialog,
              onDelete: _delete,
              onReorder: _isGrid ? null : _reorderAccounts,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      await widget.api.deleteProfile(profile.name);
      if (!mounted) return;
      showAppToast(context, title: '账号已退出', message: _profileTitle(profile));
      widget.onRefresh();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorderAccounts(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _accounts.length) {
      return;
    }
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= _accounts.length) {
      return;
    }
    final previous = List<ProfileInfo>.from(_accounts);
    final accounts = List<ProfileInfo>.from(_accounts);
    final moved = accounts.removeAt(oldIndex);
    accounts.insert(targetIndex, moved);
    final names = accounts.map((profile) => profile.name).toList(growable: false);
    setState(() => _accounts = accounts);
    try {
      // Order is already persisted; avoid bootstrap/onRefresh which used to
      // flash the whole app shell while FutureBuilder reloaded.
      await widget.api.reorderProfiles(names);
    } catch (error) {
      if (!mounted) return;
      setState(() => _accounts = previous);
      showAppErrorToast(context, message: error.toString());
    }
  }

  Future<void> _showAddAccountDialog() async {
    await showAccountEditor(
      context: context,
      api: widget.api,
      onSaved: widget.onRefresh,
      onSave: _saveNewAccount,
      onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
      onAuthorizeBaiduPan: _authorizeBaiduPan,
    );
  }

  Future<void> _showEditAccountDialog(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      final config = await widget.api.loadProfile(profile.name);
      if (!mounted) return;
      setState(() => _busy = false);
      await showAccountEditor(
        context: context,
        api: widget.api,
        initialConfig: config,
        profileName: profile.name,
        editing: true,
        onSaved: widget.onRefresh,
        onSave: (cfg) => _saveEditedAccount(profile, cfg),
        onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
        onAuthorizeBaiduPan: _authorizeBaiduPan,
      );
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<bool> _saveNewAccount(RemoteStorageConfig config) async {
    if (!config.isConfigured) {
      showAppErrorToast(
        context,
        message: config.storageType == StorageType.baiduPan
            ? '请先完成百度网盘 OAuth 授权。'
            : config.storageType == StorageType.webdav
                ? '请填写 WebDAV 地址、用户名和密码。'
                : '请填写 Endpoint、Access Key 和 Secret Key。',
      );
      return false;
    }
    setState(() => _busy = true);
    try {
      await widget.api.saveProfile(
        generateAccountProfileName(config.displayName, config.storageType),
        config,
      );
      if (!mounted) return false;
      showAppToast(context, title: '账号已保存', message: config.displayName);
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _saveEditedAccount(
    ProfileInfo profile,
    RemoteStorageConfig config,
  ) async {
    if (!config.isConfigured) {
      showAppErrorToast(context, message: '请补全账号连接信息。');
      return false;
    }
    setState(() => _busy = true);
    try {
      await widget.api.saveProfile(profile.name, config);
      if (!mounted) return false;
      showAppToast(context, title: '账号已更新', message: config.displayName);
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _startBaiduPanAuthorization() async {
    setState(() => _busy = true);
    try {
      return await widget.api.startBaiduPanAuthorization();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<RemoteStorageConfig> _authorizeBaiduPan(
    String displayName,
    String code,
  ) async {
    setState(() => _busy = true);
    try {
      return await widget.api.authorizeBaiduPan(displayName, code);
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _profileTitle(ProfileInfo profile) {
    return profile.displayName.isEmpty ? profile.name : profile.displayName;
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.theme, required this.onAddAccount});

  final ShadThemeData theme;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '账号管理',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ShadButton(onPressed: onAddAccount, child: const Text('新增账号')),
      ],
    );
  }
}
