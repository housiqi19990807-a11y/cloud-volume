// 账号管理列表复用文件列表行，直接展示所有账号而不再按类型分组。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageAccountList extends StatelessWidget {
  static const double _typeColumnWidth = 104;
  static const double _statusColumnWidth = 92;
  static const double _actionColumnWidth = 156;

  const CloudStorageAccountList({
    super.key,
    required this.accounts,
    required this.busy,
    required this.onActivate,
    required this.onDelete,
  });

  final List<ProfileInfo> accounts;
  final bool busy;
  final ValueChanged<ProfileInfo> onActivate;
  final ValueChanged<ProfileInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _AccountTableHeader(theme: theme),
          Expanded(
            child: accounts.isEmpty
                ? Center(
                    child: Text(
                      '还没有账号。',
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
                        leading: _AccountIcon(profile: profile),
                        title: _profileTitle(profile),
                        subtitleLabel: profile.endpoint,
                        sizeLabel: _storageLabel(profile),
                        sizeColumnWidthOverride: _typeColumnWidth,
                        statusWidget: _AccountStatus(active: profile.active),
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
    );
  }

  static String _profileTitle(ProfileInfo profile) {
    return profile.displayName.isEmpty ? profile.name : profile.displayName;
  }

  static String _storageLabel(ProfileInfo profile) {
    if (profile.storageType == StorageType.webdav) {
      return profile.storageType.label;
    }
    return profile.providerType.label;
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
            width: CloudStorageAccountList._typeColumnWidth,
            child: Text('类型', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: CloudStorageAccountList._statusColumnWidth,
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
  const _AccountIcon({required this.profile});

  final ProfileInfo profile;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: Icon(
        profile.storageType == StorageType.webdav
            ? LucideIcons.server
            : LucideIcons.cloud,
        size: 18,
        color: profile.active
            ? theme.colorScheme.primary
            : theme.colorScheme.mutedForeground,
      ),
    );
  }
}
