// 云存储管理页按上游类型组织账号，并提供切换与退出账号操作。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStoragePage extends StatefulWidget {
  const CloudStoragePage({
    super.key,
    required this.state,
    required this.api,
    required this.onRefresh,
    required this.onEditConfig,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onRefresh;
  final VoidCallback onEditConfig;

  @override
  State<CloudStoragePage> createState() => _CloudStoragePageState();
}

class _CloudStoragePageState extends State<CloudStoragePage> {
  StorageProviderType _selected = StorageProviderType.osca;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final active = widget.state.profiles.where((p) => p.active).firstOrNull;
    _selected = active?.providerType ?? StorageProviderType.osca;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accounts = widget.state.profiles
        .where((profile) => profile.providerType == _selected)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      '管理 OSCA、GFS、MinIO 与其他 S3 兼容对象存储账号。',
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ShadButton(
                onPressed: _busy ? null : _showAddAccountDialog,
                child: const Text('新增账号'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      for (final provider in StorageProviderType.values)
                        _providerTile(theme, provider),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: accounts.isEmpty
                      ? _emptyState(theme)
                      : ListView.separated(
                          itemCount: accounts.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) =>
                              _accountCard(theme, accounts[index]),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerTile(ShadThemeData theme, StorageProviderType provider) {
    final selected = provider == _selected;
    final count = widget.state.profiles
        .where((profile) => profile.providerType == provider)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _selected = provider),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.25)
                  : theme.colorScheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                provider == StorageProviderType.minio
                    ? LucideIcons.database
                    : LucideIcons.cloud,
                size: 18,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  provider.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('$count'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountCard(ShadThemeData theme, ProfileInfo profile) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            profile.active ? LucideIcons.checkCircle2 : LucideIcons.userRound,
            size: 18,
            color: profile.active
                ? theme.colorScheme.primary
                : theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName.isEmpty
                      ? profile.name
                      : profile.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.endpoint} · ${_maskedKey(profile.accessKeyId)}',
                  style: TextStyle(
                    color: theme.colorScheme.mutedForeground,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!profile.active)
            ShadButton.outline(
              onPressed: _busy ? null : () => _activate(profile),
              child: const Text('连接'),
            ),
          const SizedBox(width: 8),
          ShadButton.destructive(
            onPressed: _busy ? null : () => _delete(profile),
            child: const Text('退出账号'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ShadThemeData theme) {
    return Center(
      child: Text(
        '当前上游类型还没有账号。',
        style: TextStyle(color: theme.colorScheme.mutedForeground),
      ),
    );
  }

  Future<void> _activate(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      await widget.api.setActiveProfile(profile.name);
      if (!mounted) return;
      showAppToast(context, title: '已连接账号', message: profile.displayName);
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
      showAppToast(context, title: '账号已退出', message: profile.displayName);
      widget.onRefresh();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAddAccountDialog() async {
    final nameController = TextEditingController();
    final endpointController = TextEditingController();
    final regionController = TextEditingController(text: 'auto');
    final accessKeyController = TextEditingController();
    final secretKeyController = TextEditingController();
    var provider = _selected;

    await showShadDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return ShadDialog(
              title: const Text('新增云存储账号'),
              description: const Text('保存后会出现在对应上游类型的账号列表里。'),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProviderSegmentedControl(
                      value: provider,
                      onChanged: (value) =>
                          setDialogState(() => provider = value),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: nameController,
                      placeholder: const Text('账号名称'),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: endpointController,
                      placeholder: const Text('https://s3.example.com'),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: regionController,
                      placeholder: const Text('Region，例如 auto'),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: accessKeyController,
                      placeholder: const Text('Access Key ID'),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: secretKeyController,
                      placeholder: const Text('Secret Access Key'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ShadButton.outline(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 10),
                        ShadButton(
                          onPressed: () async {
                            final saved = await _saveNewAccount(
                              provider: provider,
                              name: nameController.text,
                              endpoint: endpointController.text,
                              region: regionController.text,
                              accessKey: accessKeyController.text,
                              secretKey: secretKeyController.text,
                            );
                            if (saved && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          child: const Text('保存账号'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    endpointController.dispose();
    regionController.dispose();
    accessKeyController.dispose();
    secretKeyController.dispose();
  }

  Future<bool> _saveNewAccount({
    required StorageProviderType provider,
    required String name,
    required String endpoint,
    required String region,
    required String accessKey,
    required String secretKey,
  }) async {
    final label = name.trim().isEmpty ? accessKey.trim() : name.trim();
    final config = RemoteStorageConfig.empty().copyWith(
      providerType: provider,
      displayName: label,
      endpoint: endpoint,
      region: region.trim().isEmpty ? 'auto' : region,
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
      hasSecretAccessKey: secretKey.trim().isNotEmpty,
      webdavUsername: accessKey,
      webdavPassword: secretKey,
      hasWebdavPassword: secretKey.trim().isNotEmpty,
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
      await widget.api.saveProfile(_profileNameFor(label, provider), config);
      if (!mounted) return false;
      setState(() => _selected = provider);
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

  String _maskedKey(String key) {
    if (key.length <= 6) return key.isEmpty ? '未保存 AK' : key;
    return '${key.substring(0, 4)}••••${key.substring(key.length - 2)}';
  }
}

class _ProviderSegmentedControl extends StatelessWidget {
  const _ProviderSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  final StorageProviderType value;
  final ValueChanged<StorageProviderType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in StorageProviderType.values)
          SizedBox(
            height: 36,
            child: ShadButton(
              size: ShadButtonSize.sm,
              onPressed: () => onChanged(item),
              backgroundColor: item == value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
              foregroundColor: item == value
                  ? theme.colorScheme.primaryForeground
                  : theme.colorScheme.foreground,
              child: Text(item.label),
            ),
          ),
      ],
    );
  }
}
