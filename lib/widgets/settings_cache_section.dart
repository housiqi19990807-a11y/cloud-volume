// 设置页缓存管理分区：负责目录选择、占用统计、打开目录、清空缓存与规则配置。
// 拆成独立 widget 让 settings_page.dart 保持聚焦于分区编排，避免超过 500 行。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

/// [SettingsCacheSection] 把缓存目录、统计、清理动作和规则编排进同一张卡片。
class SettingsCacheSection extends StatefulWidget {
  const SettingsCacheSection({
    super.key,
    required this.theme,
    required this.api,
    required this.config,
    required this.saving,
    required this.errorText,
    required this.stats,
    required this.loadingStats,
    required this.cleaning,
    required this.opening,
    required this.onPickDirectory,
    required this.onResetDirectory,
    required this.onRefreshStats,
    required this.onOpenDirectory,
    required this.onCleanAll,
    required this.onCleanRules,
    required this.onAutoCleanupChanged,
    required this.onMaxSizeChanged,
    required this.onMaxAgeChanged,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final bool saving;
  final String? errorText;
  final CacheStats? stats;
  final bool loadingStats;
  final bool cleaning;
  final bool opening;
  final VoidCallback onPickDirectory;
  final VoidCallback onResetDirectory;
  final VoidCallback onRefreshStats;
  final VoidCallback onOpenDirectory;
  final VoidCallback onCleanAll;
  final VoidCallback onCleanRules;
  final ValueChanged<bool> onAutoCleanupChanged;
  final ValueChanged<int> onMaxSizeChanged;
  final ValueChanged<int> onMaxAgeChanged;

  @override
  State<SettingsCacheSection> createState() => _SettingsCacheSectionState();
}

class _SettingsCacheSectionState extends State<SettingsCacheSection> {
  late final TextEditingController _maxSizeController;
  late final TextEditingController _maxAgeController;

  @override
  void initState() {
    super.initState();
    _maxSizeController = TextEditingController(
      text: widget.config.cacheMaxSizeMb.toString(),
    );
    _maxAgeController = TextEditingController(
      text: widget.config.cacheMaxAgeDays.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant SettingsCacheSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.cacheMaxSizeMb != widget.config.cacheMaxSizeMb) {
      final text = widget.config.cacheMaxSizeMb.toString();
      if (_maxSizeController.text != text) {
        _maxSizeController.text = text;
      }
    }
    if (oldWidget.config.cacheMaxAgeDays != widget.config.cacheMaxAgeDays) {
      final text = widget.config.cacheMaxAgeDays.toString();
      if (_maxAgeController.text != text) {
        _maxAgeController.text = text;
      }
    }
  }

  @override
  void dispose() {
    _maxSizeController.dispose();
    _maxAgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final hasCustomPath = widget.config.cacheDirectory.trim().isNotEmpty;
    final resolvedPath = widget.config.resolvedCacheDirectory.trim().isNotEmpty
        ? widget.config.resolvedCacheDirectory
        : '工作路径/cache';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '用于文件预览缓存和挂载读写缓存；未配置时使用工作路径下的 cache 目录。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        _InfoBlock(
          theme: theme,
          label: '缓存目录',
          value: resolvedPath,
          actions: [
            ShadButton(
              onPressed: widget.saving ? null : widget.onPickDirectory,
              child: Text(widget.saving ? '保存中...' : '选择目录'),
            ),
            ShadButton.outline(
              onPressed: widget.saving || !hasCustomPath
                  ? null
                  : widget.onResetDirectory,
              child: const Text('恢复默认'),
            ),
            if (widget.api.capabilities.supportsCacheDirectoryOpen)
              ShadButton.outline(
                onPressed: widget.opening ? null : widget.onOpenDirectory,
                child: Text(widget.opening ? '打开中...' : '打开目录'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _InfoBlock(
          theme: theme,
          label: '当前占用',
          value: _formatStats(widget.stats, widget.loadingStats),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ShadButton.outline(
              onPressed: widget.loadingStats ? null : widget.onRefreshStats,
              child: const Text('刷新统计'),
            ),
            ShadButton.outline(
              onPressed: widget.cleaning ? null : widget.onCleanRules,
              child: const Text('按规则清理'),
            ),
            ShadButton.destructive(
              onPressed: widget.cleaning ? null : widget.onCleanAll,
              child: Text(widget.cleaning ? '清理中...' : '清空缓存'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RulesEditor(
          theme: theme,
          autoEnabled: widget.config.cacheAutoCleanupEnabled,
          maxSizeController: _maxSizeController,
          maxAgeController: _maxAgeController,
          saving: widget.saving,
          onAutoChanged: widget.onAutoCleanupChanged,
          onMaxSizeChanged: widget.onMaxSizeChanged,
          onMaxAgeChanged: widget.onMaxAgeChanged,
        ),
      ],
    );
  }

  String _formatStats(CacheStats? stats, bool loading) {
    if (loading) {
      return '统计中...';
    }
    if (stats == null || !stats.exists) {
      return '暂无缓存';
    }
    final size = _humanizeBytes(stats.sizeBytes);
    if (stats.fileCount == 0) {
      return size;
    }
    return '$size · ${stats.fileCount} 个文件';
  }
}

class _RulesEditor extends StatelessWidget {
  const _RulesEditor({
    required this.theme,
    required this.autoEnabled,
    required this.maxSizeController,
    required this.maxAgeController,
    required this.saving,
    required this.onAutoChanged,
    required this.onMaxSizeChanged,
    required this.onMaxAgeChanged,
  });

  final ShadThemeData theme;
  final bool autoEnabled;
  final TextEditingController maxSizeController;
  final TextEditingController maxAgeController;
  final bool saving;
  final ValueChanged<bool> onAutoChanged;
  final ValueChanged<int> onMaxSizeChanged;
  final ValueChanged<int> onMaxAgeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
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
                      '自动清理缓存',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '启动时与运行期间每小时按规则清理一次',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadSwitch(
                value: autoEnabled,
                onChanged: saving ? null : onAutoChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '最大占用 (MB)，0 表示不限',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          ShadInput(
            controller: maxSizeController,
            keyboardType: TextInputType.number,
            placeholder: const Text('0'),
            onSubmitted: (value) =>
                onMaxSizeChanged(int.tryParse(value.trim()) ?? 0),
          ),
          const SizedBox(height: 14),
          Text(
            '最大保留天数，0 表示不限',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          ShadInput(
            controller: maxAgeController,
            keyboardType: TextInputType.number,
            placeholder: const Text('0'),
            onSubmitted: (value) =>
                onMaxAgeChanged(int.tryParse(value.trim()) ?? 0),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ShadButton(
                onPressed: saving
                    ? null
                    : () => onMaxSizeChanged(
                        int.tryParse(maxSizeController.text.trim()) ?? 0,
                      ),
                child: Text(saving ? '保存中...' : '保存规则'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.theme,
    required this.label,
    required this.value,
    this.actions = const <Widget>[],
  });

  final ShadThemeData theme;
  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// [_humanizeBytes] renders byte counts the way the file manager does.
String _humanizeBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return size >= 100 || unit == 0
      ? '${size.toStringAsFixed(0)} ${units[unit]}'
      : '${size.toStringAsFixed(2)} ${units[unit]}';
}
