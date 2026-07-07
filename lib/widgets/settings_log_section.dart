// Log settings control how much Flutter-side diagnostic data is bridged to disk.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/utils/app_log.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsLogSection extends StatefulWidget {
  const SettingsLogSection({super.key, required this.theme});

  final ShadThemeData theme;

  @override
  State<SettingsLogSection> createState() => _SettingsLogSectionState();
}

class _SettingsLogSectionState extends State<SettingsLogSection> {
  AppLogLevel _level = AppLog.level;
  bool _loading = true;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final level = await AppLog.loadLevel();
      if (!mounted) return;
      setState(() {
        _level = level;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save(AppLogLevel level) async {
    if (level == _level || _saving) return;
    setState(() {
      _level = level;
      _saving = true;
      _errorText = null;
    });
    try {
      await AppLog.setLevel(level);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '控制 Flutter 侧诊断日志写入 bridge.log 的详细程度。Debug 会包含预览耗时等高频排查日志，Release 采集时建议按需开启。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<AppLogLevel>(
            key: ValueKey<String>('app-log-level-${_level.storageValue}'),
            minWidth: 220,
            initialValue: _level,
            placeholder: Text(_level.label),
            selectedOptionBuilder: (context, selected) => Text(selected.label),
            options: AppLogLevel.values
                .map(
                  (level) => ShadOption<AppLogLevel>(
                    value: level,
                    child: Text(level.label),
                  ),
                )
                .toList(growable: false),
            onChanged: _loading || _saving
                ? null
                : (value) {
                    if (value != null) unawaited(_save(value));
                  },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _descriptionFor(_level),
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (_saving || _loading) ...[
          const SizedBox(height: 10),
          Text(
            _loading ? '正在读取日志等级...' : '正在保存日志等级...',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }

  String _descriptionFor(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.silent => '不写入 Flutter 侧应用日志。',
      AppLogLevel.error => '仅写入错误日志。',
      AppLogLevel.info => '写入错误和常规信息日志。',
      AppLogLevel.debug => '写入全部日志，包括高频调试和性能诊断。',
    };
  }
}
