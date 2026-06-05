// 回收站设置区：负责编辑桶级软删除目录名称与自动清理保留期。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TrashSettingsSection extends StatefulWidget {
  const TrashSettingsSection({
    super.key,
    required this.theme,
    required this.directoryName,
    required this.retentionDays,
    required this.saving,
    required this.errorText,
    required this.onSave,
  });

  final ShadThemeData theme;
  final String directoryName;
  final int retentionDays;
  final bool saving;
  final String? errorText;
  final Future<void> Function(String directoryName, int retentionDays) onSave;

  @override
  State<TrashSettingsSection> createState() => _TrashSettingsSectionState();
}

class _TrashSettingsSectionState extends State<TrashSettingsSection> {
  late final TextEditingController _directoryController;
  late final TextEditingController _retentionController;

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController(text: widget.directoryName);
    _retentionController = TextEditingController(
      text: widget.retentionDays.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant TrashSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directoryName != widget.directoryName) {
      _directoryController.text = widget.directoryName;
    }
    if (oldWidget.retentionDays != widget.retentionDays) {
      _retentionController.text = widget.retentionDays.toString();
    }
  }

  @override
  void dispose() {
    _directoryController.dispose();
    _retentionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '删除对象时先移入存储桶级回收站目录。默认不自动清理；保留天数设置为非负数后才会按天自动清理。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        _buildLabel(theme, '回收站目录名称'),
        const SizedBox(height: 6),
        ShadInput(
          controller: _directoryController,
          enabled: !widget.saving,
          placeholder: const Text('.trash'),
        ),
        const SizedBox(height: 14),
        _buildLabel(theme, '自动清理保留天数（-1 为关闭）'),
        const SizedBox(height: 6),
        ShadInput(
          controller: _retentionController,
          enabled: !widget.saving,
          keyboardType: TextInputType.number,
          placeholder: const Text('30'),
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
        ShadButton(
          onPressed: widget.saving
              ? null
              : () => widget.onSave(
                  _directoryController.text.trim(),
                  int.tryParse(_retentionController.text.trim()) ?? 30,
                ),
          child: Text(widget.saving ? '保存中...' : '保存回收站设置'),
        ),
      ],
    );
  }

  Widget _buildLabel(ShadThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.foreground,
      ),
    );
  }
}
