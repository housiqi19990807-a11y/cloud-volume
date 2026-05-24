// Shared SVG app mark used by the sidebar brand area and setup screen.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/yunjuan_brand.svg',
      width: size,
      height: size,
    );
  }
}
