// Log settings control how much diagnostic data the app keeps for support.

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
          '控制应用诊断日志的采集量。通常保持默认即可；排查卡顿、启动失败或文件操作异常时，可以临时切到调试。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '未手动设置时，开发调试版默认“调试”，正式发布版默认“安静”。',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
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
      AppLogLevel.silent => '不采集应用诊断日志，适合正式版日常使用。',
      AppLogLevel.error => '只记录失败和异常，适合低噪音问题采集。',
      AppLogLevel.info => '记录关键操作和错误，适合常规排查。',
      AppLogLevel.debug => '记录详细耗时和内部步骤，适合临时复现问题。',
    };
  }
}
