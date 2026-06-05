// 云存储账号二级页复用文件列表行，形成稳定的表格列和行内操作。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageAccountList extends StatelessWidget {
  static const double _accessKeyColumnWidth = 118;
  static const double _actionColumnWidth = 156;

  const CloudStorageAccountList({
    super.key,
    required this.provider,
    required this.accounts,
    required this.busy,
    required this.onBack,
    required this.onAddAccount,
    required this.onActivate,
    required this.onDelete,
  });

  final StorageProviderType provider;
  final List<ProfileInfo> accounts;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onAddAccount;
  final ValueChanged<ProfileInfo> onActivate;
  final ValueChanged<ProfileInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onBack,
              child: const Icon(LucideIcons.arrowLeft, size: 16),
            ),
            const SizedBox(width: 12),
            _ProviderIcon(provider: provider),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                provider.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onAddAccount,
              child: const Text('新增账号'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ShadCard(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                _AccountTableHeader(theme: theme),
                Expanded(
                  child: accounts.isEmpty
                      ? Center(
                          child: Text(
                            '当前上游类型还没有账号。',
                            style: TextStyle(
                              color: theme.colorScheme.mutedForeground,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: accounts.length,
                          itemBuilder: (context, index) {
                            final profile = accounts[index];
                            return FileListTile(
                              leading: _AccountIcon(active: profile.active),
                              title: _profileTitle(profile),
                              subtitleLabel: profile.endpoint,
                              sizeLabel: _maskedKey(profile.accessKeyId),
                              sizeColumnWidthOverride: _accessKeyColumnWidth,
                              statusWidget: _AccountStatus(
                                active: profile.active,
                              ),
                              trailing: _AccountActions(
                                profile: profile,
                                busy: busy,
                                onActivate: onActivate,
                                onDelete: onDelete,
                              ),
                              onTap: () {},
                              showDivider: index != accounts.length - 1,
                              deleting: busy,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _profileTitle(ProfileInfo profile) {
    return profile.displayName.isEmpty ? profile.name : profile.displayName;
  }

  static String _maskedKey(String key) {
    if (key.length <= 6) return key.isEmpty ? '未保存 AK' : key;
    return '${key.substring(0, 4)}••••${key.substring(key.length - 2)}';
  }
}

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.7);
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('账号', style: labelStyle)),
          const SizedBox(width: 12),
          SizedBox(
            width: CloudStorageAccountList._accessKeyColumnWidth,
            child: Text(
              'Access Key',
              textAlign: TextAlign.right,
              style: labelStyle,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: FileListTile.statusColumnWidth,
            child: Text('状态', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: CloudStorageAccountList._actionColumnWidth,
            child: Text('操作', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.profile,
    required this.busy,
    required this.onActivate,
    required this.onDelete,
  });

  final ProfileInfo profile;
  final bool busy;
  final ValueChanged<ProfileInfo> onActivate;
  final ValueChanged<ProfileInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CloudStorageAccountList._actionColumnWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!profile.active) ...[
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: busy ? null : () => onActivate(profile),
              child: const Text('连接'),
            ),
            const SizedBox(width: 6),
          ],
          ShadButton.destructive(
            size: ShadButtonSize.sm,
            onPressed: busy ? null : () => onDelete(profile),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

class _AccountStatus extends StatelessWidget {
  const _AccountStatus({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      active ? '已连接' : '未连接',
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.mutedForeground,
      ),
    );
  }
}

class _AccountIcon extends StatelessWidget {
  const _AccountIcon({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: Icon(
        active ? LucideIcons.checkCircle2 : LucideIcons.userRound,
        size: 18,
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.mutedForeground,
      ),
    );
  }
}

class _ProviderIcon extends StatelessWidget {
  const _ProviderIcon({required this.provider});

  final StorageProviderType provider;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Icon(
      provider == StorageProviderType.minio
          ? LucideIcons.database
          : LucideIcons.cloud,
      size: 18,
      color: theme.colorScheme.primary,
    );
  }
}
