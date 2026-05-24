// Home page is intentionally a placeholder until storage browsing features arrive.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:macos_ui/macos_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/widgets/app_shell.dart';

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
    final typography = MacosTheme.of(context).typography;
    final config = state.config;

    return AppWindowFrame(
      title: 'Remote Storage',
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('远程存储已连接', style: typography.title1),
            const SizedBox(height: 10),
            Text(
              '初始化流程已经完成。当前仓库已经能根据本地配置状态在启动时切换页面，后续可以继续接入桶浏览、文件上传和同步逻辑。',
              style: typography.body.copyWith(
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                _SummaryTile(label: 'Endpoint', value: config.endpoint),
                _SummaryTile(label: 'Bucket', value: config.bucket),
                _SummaryTile(
                  label: 'Region',
                  value: config.region.isEmpty ? 'auto / 未设置' : config.region,
                ),
                _SummaryTile(
                  label: 'Root Prefix',
                  value: config.rootPrefix.isEmpty ? '/' : config.rootPrefix,
                ),
              ],
            ),
            const SizedBox(height: 26),
            SelectableText(
              '配置文件: ${state.configPath}',
              style: typography.subheadline.copyWith(
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: onEditConfig,
                  child: const Text('编辑配置'),
                ),
                const SizedBox(width: 12),
                PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed: onRefresh,
                  child: const Text('重新检测配置'),
                ),
              ],
            ),
          ],
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
    final theme = MacosTheme.of(context);
    final typography = theme.typography;
    return SizedBox(
      width: 220,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: typography.subheadline.copyWith(
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: 10),
              Text(value, style: typography.title3),
            ],
          ),
        ),
      ),
    );
  }
}
