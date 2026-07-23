// Modal list for remote configuration backup snapshots.
// Keeps potentially long history out of the settings page body.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ConfigBackupHistoryDialog extends StatefulWidget {
  const ConfigBackupHistoryDialog({
    super.key,
    required this.api,
    required this.initialSnapshots,
    required this.onRestore,
    required this.onSnapshotsChanged,
  });

  final RemoteStorageGateway api;
  final List<ConfigBackupSnapshot> initialSnapshots;
  final Future<void> Function(ConfigBackupSnapshot snapshot) onRestore;
  final ValueChanged<List<ConfigBackupSnapshot>> onSnapshotsChanged;

  @override
  State<ConfigBackupHistoryDialog> createState() =>
      _ConfigBackupHistoryDialogState();
}

class _ConfigBackupHistoryDialogState extends State<ConfigBackupHistoryDialog> {
  late List<ConfigBackupSnapshot> _snapshots;
  bool _loading = false;
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _snapshots = List<ConfigBackupSnapshot>.from(widget.initialSnapshots);
    // Revalidate on open so the settings card can keep only a short summary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listConfigBackups();
      if (!mounted) return;
      setState(() => _snapshots = items);
      widget.onSnapshotsChanged(items);
    } catch (error) {
      if (mounted) setState(() => _error = configBackupFriendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(ConfigBackupSnapshot snapshot) async {
    setState(() => _restoring = true);
    try {
      await widget.onRestore(snapshot);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final busy = _loading || _restoring;
    return ShadDialog(
      title: const Text('配置备份历史'),
      description: const Text('按时间查看远端加密快照，选择一份后可还原账号、代理和显示排序。'),
      constraints: const BoxConstraints(maxWidth: 560),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _snapshots.isEmpty
                        ? '暂无备份'
                        : '共 ${_snapshots.length} 份备份',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: busy ? null : _refresh,
                  child: Text(_loading ? '刷新中…' : '刷新'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading && _snapshots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_snapshots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 28,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '还没有可用备份。保存目标后点“立即备份”即可创建第一份快照。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _snapshots.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final snapshot = _snapshots[index];
                    return _BackupSnapshotTile(
                      snapshot: snapshot,
                      busy: busy,
                      onRestore: () => _restore(snapshot),
                    );
                  },
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.destructive,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hover-aware snapshot row used inside the history modal.
class _BackupSnapshotTile extends StatefulWidget {
  const _BackupSnapshotTile({
    required this.snapshot,
    required this.busy,
    required this.onRestore,
  });

  final ConfigBackupSnapshot snapshot;
  final bool busy;
  final VoidCallback onRestore;

  @override
  State<_BackupSnapshotTile> createState() => _BackupSnapshotTileState();
}

class _BackupSnapshotTileState extends State<_BackupSnapshotTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interaction = ListInteractionColors.fromTheme(theme);
    final background = interaction.rowBackground(
      selected: false,
      hovered: _hovered,
      pressed: false,
    );
    final primary = configBackupSnapshotPrimaryLabel(widget.snapshot);
    final secondary = configBackupSnapshotSecondaryLabel(widget.snapshot);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primary,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      secondary,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.busy ? null : widget.onRestore,
              child: const Text('还原'),
            ),
          ],
        ),
      ),
    );
  }
}

