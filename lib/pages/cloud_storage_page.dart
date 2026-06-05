// 云存储管理页负责两级页面状态，并把具体卡片与列表交给 widgets 复用。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/cloud_storage_account_list.dart';
import 'package:remote_storage/widgets/cloud_storage_provider_overview.dart';
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
  StorageProviderType? _selectedProvider;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final selected = _selectedProvider;
    final accounts = selected == null
        ? const <ProfileInfo>[]
        : widget.state.profiles
              .where((profile) => profile.providerType == selected)
              .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            theme: theme,
            inProviderPage: selected != null,
            onAddAccount: () => _showAddAccountDialog(selected),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: selected == null
                ? CloudStorageProviderOverview(
                    profiles: widget.state.profiles,
                    onOpenProvider: (provider) =>
                        setState(() => _selectedProvider = provider),
                    onAddAccount: _showAddAccountDialog,
                  )
                : CloudStorageAccountList(
                    provider: selected,
                    accounts: accounts,
                    busy: _busy,
                    onBack: () => setState(() => _selectedProvider = null),
                    onAddAccount: () => _showAddAccountDialog(selected),
                    onActivate: _activate,
                    onDelete: _delete,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _activate(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      await widget.api.setActiveProfile(profile.name);
      if (!mounted) return;
      showAppToast(context, title: '已连接账号', message: _profileTitle(profile));
      widget.onRefresh();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _showAddAccountDialog([StorageProviderType? provider]) async {
    final active = widget.state.profiles.where((p) => p.active).firstOrNull;
    await showShadDialog<void>(
      context: context,
      builder: (_) => CloudStorageAccountDialog(
        initialProvider:
            provider ??
            _selectedProvider ??
            active?.providerType ??
            StorageProviderType.osca,
        onSave: _saveNewAccount,
      ),
    );
  }

  Future<bool> _saveNewAccount(CloudStorageAccountDraft draft) async {
    final label = draft.name.trim().isEmpty
        ? draft.accessKey.trim()
        : draft.name.trim();
    final config = RemoteStorageConfig.empty().copyWith(
      providerType: draft.provider,
      displayName: label,
      endpoint: draft.endpoint,
      region: draft.region.trim().isEmpty ? 'auto' : draft.region,
      accessKeyId: draft.accessKey,
      secretAccessKey: draft.secretKey,
      hasSecretAccessKey: draft.secretKey.trim().isNotEmpty,
      webdavUsername: draft.accessKey,
      webdavPassword: draft.secretKey,
      hasWebdavPassword: draft.secretKey.trim().isNotEmpty,
    );
    if (!config.isConfigured) {
      showAppErrorToast(
        context,
        message: '请填写 Endpoint、Access Key 和 Secret Key。',
      );
      return false;
    }
    setState(() => _busy = true);
    try {
      await widget.api.saveProfile(
        _profileNameFor(label, draft.provider),
        config,
      );
      if (!mounted) return false;
      setState(() => _selectedProvider = draft.provider);
      showAppToast(context, title: '账号已保存', message: label);
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _profileNameFor(String label, StorageProviderType provider) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = normalized.isEmpty ? provider.storageValue : normalized;
    return '${provider.storageValue}-$base-${DateTime.now().millisecondsSinceEpoch}';
  }

  static String _profileTitle(ProfileInfo profile) {
    return profile.displayName.isEmpty ? profile.name : profile.displayName;
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.theme,
    required this.inProviderPage,
    required this.onAddAccount,
  });

  final ShadThemeData theme;
  final bool inProviderPage;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '云存储管理',
                style: theme.textTheme.h3.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                inProviderPage
                    ? '查看当前上游类型下的账号，连接或退出具体账号。'
                    : '选择一个上游类型，再管理它下面的多个云存储账号。',
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        ShadButton(onPressed: onAddAccount, child: const Text('新增账号')),
      ],
    );
  }
}
