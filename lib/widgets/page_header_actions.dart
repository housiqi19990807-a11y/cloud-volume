// 通用页面头部操作区：宽度充足时平铺所有按钮，不足时把次操作收进「…」下拉菜单，
// 防止右侧按钮挤压标题列导致副标题错位断行。

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 供 [PageHeaderActions.secondary] 使用的次操作描述。
///
/// 宽度充足时通过 [builder] 渲染为平铺按钮；不足时改用 [label] / [onPressed]
/// 渲染为 [ShadContextMenuItem]，收进「…」更多操作菜单。
class SecondaryAction {
  const SecondaryAction({
    required this.label,
    required this.builder,
    this.onPressed,
    this.enabled = true,
  });

  /// 菜单项显示文案（折叠后使用）。
  final String label;

  /// 平铺形态的 widget 工厂（展开时使用）。
  final WidgetBuilder builder;

  /// 菜单项回调；为 `null` 时菜单项置灰。
  final VoidCallback? onPressed;

  /// 菜单项是否可用。
  final bool enabled;
}

/// 溢出菜单分组 id，保证同一时刻只有一个页面头部菜单打开。
const Object _pageHeaderOverflowGroup = Object();

/// 页面头部响应式操作区。
///
/// [primary] 始终平铺；[secondary] 在可用宽度低于 [overflowThreshold] 时收进
/// 「…」下拉菜单（[LucideIcons.ellipsisVertical] + [ShadContextMenu]）。
/// primary 与 secondary 同时为空时返回 [SizedBox.shrink]。
class PageHeaderActions extends StatelessWidget {
  const PageHeaderActions({
    super.key,
    this.primary = const [],
    this.secondary = const [],
    this.overflowThreshold = 520,
    this.spacing = 8,
  });

  /// 始终平铺的主操作（核心按钮 / 选中徽标）。
  final List<Widget> primary;

  /// 宽度不足时折叠进菜单的次操作。
  final List<SecondaryAction> secondary;

  /// 触发折叠的可用宽度阈值。
  final double overflowThreshold;

  /// 主操作之间的水平间距。
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (primary.isEmpty && secondary.isEmpty) {
      return const SizedBox.shrink();
    }
    // 没有次操作时无需测量宽度，直接平铺主操作。
    if (secondary.isEmpty) {
      return _wrap(primary, spacing);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= overflowThreshold;
        final actions = <Widget>[...primary];
        if (expanded) {
          actions.addAll(
            secondary.map((action) => action.builder(context)),
          );
        } else {
          actions.add(_OverflowMenuButton(actions: secondary));
        }
        return _wrap(actions, spacing);
      },
    );
  }

  Widget _wrap(List<Widget> children, double space) {
    return Wrap(
      spacing: space,
      runSpacing: space,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: children,
    );
  }
}

/// 头部「…」更多操作按钮：复用 [ShadContextMenu] + [DesktopContextMenuRegistry] 的
/// 既有模式（与 file_manager_bucket_browser_actions `_BucketOverflowMenuButton` 一致），
/// 点击在按钮下方弹出菜单。
class _OverflowMenuButton extends StatefulWidget {
  const _OverflowMenuButton({required this.actions});

  final List<SecondaryAction> actions;

  @override
  State<_OverflowMenuButton> createState() => _OverflowMenuButtonState();
}

class _OverflowMenuButtonState extends State<_OverflowMenuButton> {
  final GlobalKey _buttonKey = GlobalKey();
  late final ShadContextMenuController _controller;
  Offset? _menuAnchorOffset;

  @override
  void initState() {
    super.initState();
    _controller = ShadContextMenuController();
    _controller.addListener(_syncActiveController);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncActiveController);
    DesktopContextMenuRegistry.deactivate(_pageHeaderOverflowGroup, _controller);
    _controller.dispose();
    super.dispose();
  }

  void _syncActiveController() {
    if (_controller.isOpen) {
      DesktopContextMenuRegistry.activate(_pageHeaderOverflowGroup, _controller);
      return;
    }
    DesktopContextMenuRegistry.deactivate(_pageHeaderOverflowGroup, _controller);
  }

  /// 再次点击「更多」图标时收起菜单。
  void _toggleMenu() {
    if (widget.actions.isEmpty) {
      return;
    }
    if (_controller.isOpen) {
      _controller.hide();
      return;
    }
    final buttonContext = _buttonKey.currentContext;
    if (!mounted || buttonContext == null) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    setState(() {
      _menuAnchorOffset = topLeft + Offset(0, box.size.height + 4);
    });
    _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadContextMenu(
      anchor: _menuAnchorOffset == null
          ? null
          : ShadGlobalAnchor(_menuAnchorOffset!),
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 176),
      effects: const [],
      popoverReverseDuration: Duration.zero,
      items: widget.actions
          .map(
            (action) => ShadContextMenuItem(
              onPressed: action.enabled ? action.onPressed : null,
              child: Text(action.label),
            ),
          )
          .toList(growable: false),
      child: KeyedSubtree(
        key: _buttonKey,
        child: ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: _toggleMenu,
          child: Icon(
            LucideIcons.ellipsisVertical,
            size: 16,
            color: theme.colorScheme.foreground,
          ),
        ),
      ),
    );
  }
}
