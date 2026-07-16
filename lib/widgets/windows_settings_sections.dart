// Windows settings sections keep mount-specific controls out of the shared settings widget file.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class WindowsMountModeSection extends StatelessWidget {
  const WindowsMountModeSection({
    super.key,
    required this.theme,
    required this.mode,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final WindowsMountMode mode;
  final bool saving;
  final String? errorText;
  final ValueChanged<WindowsMountMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Windows 可以在两种 Cloud Files 读路径和一个纯 WebDAV 回退模式之间切换。切换后请重新挂载 bucket 再验证效果。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<WindowsMountMode>(
            key: ValueKey<WindowsMountMode>(mode),
            minWidth: 320,
            initialValue: mode,
            placeholder: Text(_mountModeLabel(mode)),
            selectedOptionBuilder: (context, selected) =>
                Text(_mountModeLabel(selected)),
            options: WindowsMountMode.values
                .map(
                  (item) => ShadOption<WindowsMountMode>(
                    value: item,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_mountModeLabel(item)),
                        const SizedBox(height: 2),
                        Text(
                          _mountModeDescription(item),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: saving ? null : onChanged,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }

  static String _mountModeLabel(WindowsMountMode mode) {
    return switch (mode) {
      WindowsMountMode.cloudFilesCached => 'Cloud Files + 本地缓存/异步同步',
      WindowsMountMode.cloudFilesDirect => 'Cloud Files + 直连 S3',
      WindowsMountMode.webdav => '纯 WebDAV 映射盘',
    };
  }

  static String _mountModeDescription(WindowsMountMode mode) {
    return switch (mode) {
      WindowsMountMode.cloudFilesCached =>
        '使用 Cloud Files 外壳，但文件读写回到现有缓存、下载任务和异步写回链路。',
      WindowsMountMode.cloudFilesDirect =>
        '使用 Cloud Files 外壳，按需读取时直接请求远端对象，便于对比直连效果。',
      WindowsMountMode.webdav => '保留旧的映射盘回退模式，便于兼容性排查。',
    };
  }
}

class WindowsMountEngineSection extends StatefulWidget {
  const WindowsMountEngineSection({
    super.key,
    required this.theme,
    required this.engine,
    required this.capacityGb,
    required this.winFspAvailable,
    required this.installingWinFsp,
    required this.saving,
    required this.errorText,
    required this.onEngineChanged,
    required this.onCapacitySaved,
    required this.onInstallWinFsp,
  });

  final ShadThemeData theme;
  final WindowsMountEngine engine;
  final int capacityGb;
  final bool winFspAvailable;
  final bool installingWinFsp;
  final bool saving;
  final String? errorText;
  final ValueChanged<WindowsMountEngine> onEngineChanged;
  final ValueChanged<int> onCapacitySaved;
  final VoidCallback onInstallWinFsp;

  @override
  State<WindowsMountEngineSection> createState() =>
      _WindowsMountEngineSectionState();
}

class _WindowsMountEngineSectionState
    extends State<WindowsMountEngineSection> {
  late final TextEditingController _capacityController;

  @override
  void initState() {
    super.initState();
    _capacityController = TextEditingController(
      text: widget.capacityGb.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant WindowsMountEngineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.capacityGb != oldWidget.capacityGb) {
      _capacityController.text = widget.capacityGb.toString();
    }
  }

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cloud Files 是默认内核，保留占位文件、按需下载和现有写回链路。WinFsp 提供真正的虚拟文件系统卷，可向 Explorer 报告自定义容量，但需要先安装 WinFsp 2025。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<WindowsMountEngine>(
            key: ValueKey<WindowsMountEngine>(widget.engine),
            minWidth: 320,
            initialValue: widget.engine,
            ensureSelectedVisible: false,
            selectedOptionBuilder: (context, value) =>
                Text(_engineLabel(value)),
            options: WindowsMountEngine.values
                .where((engine) =>
                    engine != WindowsMountEngine.winFsp ||
                    widget.winFspAvailable)
                .map(
                  (engine) => ShadOption<WindowsMountEngine>(
                    value: engine,
                    child: Text(_engineLabel(engine)),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.saving
                ? null
                : (value) {
                    if (value != null) widget.onEngineChanged(value);
                  },
          ),
        ),
        if (!widget.winFspAvailable) ...[
          const SizedBox(height: 10),
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
                  '未检测到 WinFsp 驱动。应用已内嵌安装包，点击下方按钮即可静默安装（会弹出 UAC 确认）。安装后即可选择 WinFsp 虚拟文件系统引擎。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ShadButton.outline(
            onPressed: (widget.saving || widget.installingWinFsp)
                ? null
                : widget.onInstallWinFsp,
            child: Text(widget.installingWinFsp ? '正在安装 WinFsp...' : '安装 WinFsp'),
          ),
        ],
        if (widget.engine == WindowsMountEngine.winFsp) ...[
          const SizedBox(height: 16),
          Text(
            '虚拟总容量',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ShadInput(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  enabled: !widget.saving,
                  placeholder: const Text('1024'),
                ),
              ),
              const SizedBox(width: 8),
              Text('GB', style: theme.textTheme.small),
              const SizedBox(width: 12),
              ShadButton.outline(
                onPressed: widget.saving
                    ? null
                    : () {
                        final value = int.tryParse(
                          _capacityController.text.trim(),
                        );
                        widget.onCapacitySaved(value ?? 0);
                      },
                child: Text(widget.saving ? '保存中...' : '保存容量'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '仅控制 WinFsp 卷在 Explorer 中显示的总容量；不改变云端配额或本地缓存上限。',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
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
      ],
    );
  }

  String _engineLabel(WindowsMountEngine engine) {
    return switch (engine) {
      WindowsMountEngine.cloudFiles => 'Cloud Files（默认）',
      WindowsMountEngine.winFsp => 'WinFsp 虚拟文件系统',
    };
  }
}

class WindowsWritebackConcurrencySection extends StatelessWidget {
  const WindowsWritebackConcurrencySection({
    super.key,
    required this.theme,
    required this.concurrency,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  static const List<int> _options = <int>[1, 2, 4, 6, 8, 12, 16, 24, 32];

  final ShadThemeData theme;
  final int concurrency;
  final bool saving;
  final String? errorText;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '限制挂载写回同时上传的文件数，避免大批量复制时一下子并发几十上百个上传把 UI、网络和对象存储都打满。修改后请重新挂载 bucket 再生效。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<int>(
            key: ValueKey<int>(concurrency),
            minWidth: 220,
            initialValue: concurrency,
            placeholder: Text('$concurrency 个并发上传'),
            selectedOptionBuilder: (context, selected) =>
                Text('$selected 个并发上传'),
            options: _options
                .map(
                  (item) =>
                      ShadOption<int>(value: item, child: Text('$item 个并发上传')),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) {
                    if (value != null) {
                      onChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '建议从 2 到 8 开始。目录树很大、单文件又不大的场景，值越大越容易把任务队列和后端压力同时放大。',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

class WindowsMountRecoverySection extends StatelessWidget {
  const WindowsMountRecoverySection({
    super.key,
    required this.theme,
    required this.busy,
    required this.cleaningProcesses,
    required this.errorText,
    required this.onReset,
    required this.onCleanupProcesses,
  });

  final ShadThemeData theme;
  final bool busy;
  final bool cleaningProcesses;
  final String? errorText;
  final VoidCallback onReset;
  final VoidCallback onCleanupProcesses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '当 Cloud Files 或 WebDAV 挂载状态卡住时，这个兜底操作会强制清理当前挂载、残留 sync root 和前端挂载状态，方便重新验证挂载与写入流程。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '强制卸载并重置挂载状态',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '会调用底层 cleanup_mounts，对当前 bucket 挂载、旧 sync root、This PC 入口和本地挂载状态做一次兜底清理。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 12),
        ShadButton.outline(
          onPressed: cleaningProcesses ? null : onCleanupProcesses,
          child: Text(cleaningProcesses ? '正在结束残留进程...' : '结束残留占用进程'),
        ),
        const SizedBox(height: 10),
        ShadButton.destructive(
          onPressed: busy ? null : onReset,
          child: Text(busy ? '正在重置...' : '强制卸载并重置状态'),
        ),
      ],
    );
  }
}
