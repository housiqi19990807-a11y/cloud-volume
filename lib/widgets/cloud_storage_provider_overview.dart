// 账号统计条保留轻量概览，不再作为分组导航入口。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageProviderOverview extends StatelessWidget {
  const CloudStorageProviderOverview({super.key, required this.profiles});

  final List<ProfileInfo> profiles;

  @override
  Widget build(BuildContext context) {
    final s3Count = profiles
        .where((p) => p.storageType == StorageType.s3)
        .length;
    final webdavCount = profiles
        .where((p) => p.storageType == StorageType.webdav)
        .length;
    return Row(
      children: [
        _StatCard(
          icon: LucideIcons.cloud,
          label: StorageType.s3.label,
          count: s3Count,
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: LucideIcons.server,
          label: StorageType.webdav.label,
          count: webdavCount,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Expanded(
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
