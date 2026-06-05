// 云存储上游总览用系统卡片样式承载一级入口与账号概览。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageProviderOverview extends StatelessWidget {
  const CloudStorageProviderOverview({
    super.key,
    required this.profiles,
    required this.onOpenProvider,
    required this.onAddAccount,
  });

  final List<ProfileInfo> profiles;
  final ValueChanged<StorageProviderType> onOpenProvider;
  final ValueChanged<StorageProviderType> onAddAccount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: StorageProviderType.values.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 158,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemBuilder: (context, index) {
        final provider = StorageProviderType.values[index];
        final providerProfiles = profiles
            .where((profile) => profile.providerType == provider)
            .toList(growable: false);
        final active = providerProfiles.where((p) => p.active).firstOrNull;
        return _ProviderCard(
          provider: provider,
          count: providerProfiles.length,
          activeName: active == null
              ? ''
              : active.displayName.isEmpty
              ? active.name
              : active.displayName,
          onOpen: () => onOpenProvider(provider),
          onAddAccount: () => onAddAccount(provider),
        );
      },
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.count,
    required this.activeName,
    required this.onOpen,
    required this.onAddAccount,
  });

  final StorageProviderType provider;
  final int count;
  final String activeName;
  final VoidCallback onOpen;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ProviderIcon(provider: provider, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '$count 个账号',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.foreground,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                activeName.isEmpty ? '暂无已连接账号' : '已连接 $activeName',
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: onAddAccount,
                  child: const Text('添加账号'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderIcon extends StatelessWidget {
  const _ProviderIcon({required this.provider, required this.size});

  final StorageProviderType provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Icon(
        provider == StorageProviderType.minio
            ? LucideIcons.database
            : LucideIcons.cloud,
        size: 18,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
