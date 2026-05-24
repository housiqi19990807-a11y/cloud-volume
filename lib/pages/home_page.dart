// 主页：存储连接成功后的占位页，等待后续桶浏览和文件管理功能。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onEditConfig,
  });

  final BootstrapState state;
  final VoidCallback onRefresh;
  final VoidCallback onEditConfig;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = state.config;

    // Full-bleed background extending behind transparent titlebar.
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Padding(
        // Safe zone for macOS traffic lights.
        padding: const EdgeInsets.only(top: 40),
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '远程存储已连接',
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '初始化完成。应用已根据本地配置状态完成页面切换。'
                    '下一步：集成存储桶浏览、文件上传及同步逻辑。',
                    style: TextStyle(
                      color: theme.colorScheme.mutedForeground,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SummaryTile(label: '端点', value: config.endpoint),
                      _SummaryTile(label: '存储桶', value: config.bucket),
                      _SummaryTile(
                        label: '区域',
                        value: config.region.isEmpty
                            ? 'auto / 未设置'
                            : config.region,
                      ),
                      _SummaryTile(
                        label: '根前缀',
                        value: config.rootPrefix.isEmpty
                            ? '/'
                            : config.rootPrefix,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    '配置文件：${state.configPath}',
                    style: TextStyle(
                      color: theme.colorScheme.mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      ShadButton(
                        onPressed: onEditConfig,
                        child: const Text('编辑配置'),
                      ),
                      const SizedBox(width: 10),
                      ShadButton.outline(
                        onPressed: onRefresh,
                        child: const Text('重新检测配置'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
