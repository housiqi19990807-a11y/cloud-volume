// Shared brand logo used by the sidebar and setup screen.

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/app_brand_logo_svg.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.height = 40, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeController.of(context).accent.color;
    return SvgPicture.string(
      buildAppBrandLogoSvg(accent),
      height: height,
      width: width,
    );
  }
}
