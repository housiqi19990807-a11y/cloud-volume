// Android 列表多选模式的底部动作条：顶行「取消 | 已选中 N 个 X | 全选」，
// 下方一行批量动作。平铺无边框（mobile_ui 基线），行间发丝分隔线与列表
// 行同规格；所有触控目标 ≥48dp，底部避让手势导航安全区。页内用法：列表
// 下方 AnimatedSize 包裹，选中集非空时出现、清空时收起。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// One action button in the bottom selection bar.
class MobileSelectionAction {
  const MobileSelectionAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// Destructive actions (彻底删除/清理) render in the destructive color.
  final bool destructive;

  /// Disabled actions render muted and swallow the press (e.g. while a batch
  /// action is already running).
  final bool enabled;
}

/// Bottom bar shown while a mobile list has a selection. The title slot of
/// the page stays stable; this bar owns the selection count, select-all and
/// the batch actions.
class MobileSelectionActionBar extends StatelessWidget {
  const MobileSelectionActionBar({
    super.key,
    required this.selectedCount,
    required this.countLabel,
    required this.onCancelSelection,
    required this.onSelectAll,
    required this.actions,
  });

  final int selectedCount;

  /// Noun used in the count line, e.g. 文件 / 任务.
  final String countLabel;
  final VoidCallback onCancelSelection;
  final VoidCallback onSelectAll;
  final List<MobileSelectionAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hairline = BorderSide(
      color: theme.colorScheme.border.withValues(alpha: 0.55),
      width: 0.6,
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(border: Border(top: hairline)),
      // 轻度水平内缩，让条上按钮与列表行内容（行内另有 12dp 内距）对齐。
      padding: EdgeInsets.fromLTRB(4, 0, 4, bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _textButton(
                context,
                label: '取消',
                color: theme.colorScheme.foreground,
                onPressed: onCancelSelection,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '已选中 $selectedCount 个$countLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                ),
              ),
              _textButton(
                context,
                label: '全选',
                color: theme.colorScheme.foreground,
                onPressed: onSelectAll,
              ),
            ],
          ),
          Container(decoration: BoxDecoration(border: Border(bottom: hairline))),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Wrap(
              spacing: 4,
              children: [
                for (final action in actions)
                  _actionButton(context, action, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textButton(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      child: ShadButton.ghost(
        height: 48,
        onPressed: onPressed,
        child: Text(label, style: TextStyle(fontSize: 13, color: color)),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    MobileSelectionAction action,
    ShadThemeData theme,
  ) {
    final color = !action.enabled
        ? theme.colorScheme.mutedForeground
        : action.destructive
        ? theme.colorScheme.destructive
        : theme.colorScheme.primary;
    return Semantics(
      button: true,
      child: ShadButton.ghost(
        height: 48,
        onPressed: action.enabled ? action.onPressed : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(action.label, style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ),
    );
  }
}
