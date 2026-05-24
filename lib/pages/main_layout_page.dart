// 主布局：侧边栏导航 + 右侧内容区。
// 侧边栏使用渐变背景 + 装饰圆形，风格与登录页左侧品牌面板统一。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/pages/settings_page.dart';
import 'package:remote_storage/pages/transfers_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/local_cloudpan_sidebar_icon.dart';
import 'package:remote_storage/widgets/sidebar_transfer_status.dart';

/// 侧边栏菜单项。
enum SidebarItem { fileManager, transfers, settings }

class MainLayoutPage extends StatefulWidget {
  const MainLayoutPage({
    super.key,
    required this.state,
    required this.api,
    required this.onEditConfig,
    required this.onRefresh,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;

  @override
  State<MainLayoutPage> createState() => _MainLayoutPageState();
}

class _MainLayoutPageState extends State<MainLayoutPage> {
  SidebarItem _selected = SidebarItem.fileManager;

  @override
  void initState() {
    super.initState();
    TransferQueue.instance.bindApi(widget.api);
  }

  @override
  void didUpdateWidget(covariant MainLayoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      TransferQueue.instance.bindApi(widget.api);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final ac = ThemeController.of(context).accent.color;
    final bgTop = Color.lerp(const Color(0xffeef3ff), ac, 0.08)!;
    final bgBottom = Color.lerp(const Color(0xfff8faff), ac, 0.03)!;
    final heading = Color.lerp(const Color(0xff1e293b), ac, 0.15)!;
    final muted = Color.lerp(const Color(0xff64748b), ac, 0.06)!;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: Stack(
        children: [
          // 装饰圆形。
          Positioned(
            top: -40,
            right: -30,
            child: _circle(140, ac.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: 80,
            left: -40,
            child: _circle(120, ac.withValues(alpha: 0.04)),
          ),
          Positioned(
            top: 280,
            right: 20,
            child: _circle(50, ac.withValues(alpha: 0.03)),
          ),
          Positioned(
            bottom: 200,
            right: -20,
            child: _circle(80, ac.withValues(alpha: 0.06)),
          ),
          // 前景内容。
          Padding(
            padding: const EdgeInsets.only(top: 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 品牌标识：图标 + 应用名。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              ac.withValues(alpha: 0.15),
                              ac.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: ac.withValues(alpha: 0.2)),
                        ),
                        child: LocalCloudPanSidebarIcon(
                          glyph: LocalCloudPanSidebarGlyph.fileManager,
                          size: 18,
                          color: ac,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remote Storage',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: heading,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '远程存储管理',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ac.withValues(alpha: 0.2),
                          ac.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // 菜单项。
                _navItem(
                  LocalCloudPanSidebarGlyph.fileManager,
                  '文件管理',
                  SidebarItem.fileManager,
                  ac,
                  muted,
                ),
                _navItem(
                  LocalCloudPanSidebarGlyph.transfers,
                  '传输管理',
                  SidebarItem.transfers,
                  ac,
                  muted,
                ),
                _navItemWidget(
                  Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: _selected == SidebarItem.settings ? ac : muted,
                  ),
                  '系统设置',
                  SidebarItem.settings,
                  ac,
                  muted,
                ),
                const Spacer(),
                SidebarTransferStatus(
                  accent: ac,
                  muted: muted,
                  onTap: () =>
                      setState(() => _selected = SidebarItem.transfers),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _navItem(
    LocalCloudPanSidebarGlyph icon,
    String label,
    SidebarItem item,
    Color ac,
    Color muted,
  ) {
    final selected = _selected == item;
    final bg = selected ? ac.withValues(alpha: 0.1) : Colors.transparent;
    final fg = selected ? ac : muted;
    final border = selected
        ? Border.all(color: ac.withValues(alpha: 0.2))
        : Border.all(color: Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _selected = item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          child: Row(
            children: [
              LocalCloudPanSidebarIcon(glyph: icon, size: 17, color: fg),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItemWidget(
    Widget leading,
    String label,
    SidebarItem item,
    Color ac,
    Color muted,
  ) {
    final selected = _selected == item;
    final bg = selected ? ac.withValues(alpha: 0.1) : Colors.transparent;
    final fg = selected ? ac : muted;
    final border = selected
        ? Border.all(color: ac.withValues(alpha: 0.2))
        : Border.all(color: Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _selected = item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final index = switch (_selected) {
      SidebarItem.fileManager => 0,
      SidebarItem.transfers => 1,
      SidebarItem.settings => 2,
    };

    return IndexedStack(
      index: index,
      children: [
        FileManagerPage(api: widget.api, config: widget.state.config),
        TransfersPage(api: widget.api, config: widget.state.config),
        SettingsPage(
          state: widget.state,
          onEditConfig: widget.onEditConfig,
          onRefresh: widget.onRefresh,
        ),
      ],
    );
  }
}
