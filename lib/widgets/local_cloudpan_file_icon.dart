// Local-cloudPan SVG 图标映射：沿用用户旧项目的文件类型资源，统一服务列表和网格视图。

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Local-cloudPan 文件图标组件。
class LocalCloudPanFileIcon extends StatelessWidget {
  const LocalCloudPanFileIcon({
    super.key,
    required this.name,
    required this.size,
    this.isDirectory = false,
    this.isBucket = false,
  });

  final String name;
  final double size;
  final bool isDirectory;
  final bool isBucket;

  @override
  Widget build(BuildContext context) {
    final assetPath = localCloudPanIconPathFor(
      name,
      isDirectory: isDirectory,
      isBucket: isBucket,
    );

    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        assetPath,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x14000000),
              borderRadius: BorderRadius.circular(size * 0.22),
            ),
          ),
        ),
      ),
    );
  }
}

/// 根据文件名和对象类型返回 Local-cloudPan SVG 资源。
String localCloudPanIconPathFor(
  String name, {
  bool isDirectory = false,
  bool isBucket = false,
}) {
  if (isBucket) {
    return 'assets/icons/local_cloudpan/sidebar/bucket.svg';
  }
  if (isDirectory) {
    return 'assets/icons/local_cloudpan/fileType/directory.svg';
  }

  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const base = 'assets/icons/local_cloudpan/fileType';

  switch (ext) {
    case 'mp3':
    case 'mpeg':
    case 'ram':
    case 'rm':
    case 'swf':
    case 'wma':
      return '$base/audio/${ext == 'jpeg' ? 'jpg' : ext}.svg';
    case '7z':
    case 'gzip':
    case 'rar':
    case 'tar':
    case 'zip':
      return '$base/compression/$ext.svg';
    case 'doc':
    case 'docx':
    case 'md':
    case 'pdf':
    case 'ppt':
    case 'pptx':
    case 'txt':
    case 'xls':
    case 'xlsx':
      return '$base/document/$ext.svg';
    case 'bmp':
    case 'gif':
    case 'jfif':
    case 'jpeg':
    case 'jpg':
    case 'png':
      return '$base/picture/${ext == 'jpeg' ? 'jpg' : ext}.svg';
    case 'svg':
      return '$base/picture/svg.svg';
    case 'avi':
    case 'flv':
    case 'm4v':
    case 'mkv':
    case 'mov':
    case 'mp4':
    case 'mpg':
    case 'rmvb':
    case 'wmv':
      return '$base/video/$ext.svg';
    default:
      return '$base/others.svg';
  }
}
