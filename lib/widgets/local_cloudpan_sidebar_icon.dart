// Local-cloudPan 风格的侧边栏图标：统一文件管理、传输、设置与品牌入口的视觉语言。

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 侧边栏图标资源枚举。
enum LocalCloudPanSidebarGlyph {
  fileManager('assets/icons/local_cloudpan/sidebar/file-manager.svg'),
  transfers('assets/icons/local_cloudpan/sidebar/transfers.svg'),
  settings('assets/icons/local_cloudpan/sidebar/settings.svg');

  const LocalCloudPanSidebarGlyph(this.assetPath);

  final String assetPath;
}

/// 侧边栏 SVG 图标，支持跟随导航前景色变化。
class LocalCloudPanSidebarIcon extends StatelessWidget {
  const LocalCloudPanSidebarIcon({
    super.key,
    required this.glyph,
    required this.size,
    required this.color,
  });

  final LocalCloudPanSidebarGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        glyph.assetPath,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}
