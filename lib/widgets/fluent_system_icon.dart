// Fluent System Icon 封装：统一导航、桶和状态入口的 SVG 加载与着色。

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 项目内使用的 Fluent System Icon 资源。
enum FluentSystemGlyph {
  brand('assets/icons/fluent/server_link_20_regular.svg'),
  fileManager('assets/icons/fluent/document_one_page_multiple_20_regular.svg'),
  transfers('assets/icons/fluent/arrow_sync_circle_20_regular.svg'),
  settings('assets/icons/fluent/settings_20_regular.svg'),
  bucket('assets/icons/fluent/hard_drive_24_filled.svg');

  const FluentSystemGlyph(this.assetPath);

  final String assetPath;
}

/// Fluent SVG 图标，默认跟随当前前景色。
class FluentSystemIcon extends StatelessWidget {
  const FluentSystemIcon({
    super.key,
    required this.glyph,
    required this.size,
    this.color,
  });

  final FluentSystemGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color;
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        glyph.assetPath,
        fit: BoxFit.contain,
        colorFilter: resolvedColor == null
            ? null
            : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      ),
    );
  }
}
