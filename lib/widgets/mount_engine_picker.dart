// Windows mount engine quick selector for the mount dialog. Extracted so the
// main dialog file stays focused on presentation/read-only/path choices.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Compact engine dropdown shown only on Windows. When WinFsp is not installed
/// the WinFsp option is hidden and a short note points the user to Settings.
class MountEnginePicker extends StatelessWidget {
  const MountEnginePicker({
    super.key,
    required this.theme,
    required this.engine,
    required this.winFspAvailable,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final WindowsMountEngine engine;
  final bool winFspAvailable;
  final ValueChanged<WindowsMountEngine> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '挂载引擎',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<WindowsMountEngine>(
            key: ValueKey<WindowsMountEngine>(engine),
            minWidth: 440,
            initialValue: engine,
            ensureSelectedVisible: false,
            selectedOptionBuilder: (context, value) =>
                Text(_engineLabel(value)),
            options: WindowsMountEngine.values
                .where((item) =>
                    item != WindowsMountEngine.winFsp || winFspAvailable)
                .map(
                  (item) => ShadOption<WindowsMountEngine>(
                    value: item,
                    child: Text(_engineLabel(item)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
        if (!winFspAvailable) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.info,
                size: 15,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '未检测到 WinFsp 驱动，如需使用虚拟文件系统卷请先在「设置 - Windows 挂载高级设置」中安装。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _engineLabel(WindowsMountEngine engine) {
    return switch (engine) {
      WindowsMountEngine.cloudFiles => 'Cloud Files（默认）',
      WindowsMountEngine.winFsp => 'WinFsp 虚拟文件系统',
    };
  }
}

