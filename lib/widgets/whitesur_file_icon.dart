// WhiteSur SVG 图标映射：按远程对象类型和扩展名选择接近 Finder 的图标资源。

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// WhiteSur 资源描述，供列表和网格视图复用。
class WhiteSurIconSpec {
  const WhiteSurIconSpec(this.assetPath);

  final String assetPath;
}

/// WhiteSur SVG 文件图标，统一封装尺寸和加载占位。
class WhiteSurFileIcon extends StatelessWidget {
  const WhiteSurFileIcon({
    super.key,
    required this.assetPath,
    required this.size,
  });

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
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

/// 根据对象名选择 WhiteSur 图标。
WhiteSurIconSpec whiteSurIconForEntry(
  String name, {
  bool isDirectory = false,
  bool isBucket = false,
}) {
  if (isBucket) {
    return const WhiteSurIconSpec(
      'assets/icons/whitesur/places/network-server-balanced.svg',
    );
  }
  if (isDirectory) {
    return WhiteSurIconSpec(_folderAssetForName(name));
  }
  return WhiteSurIconSpec(_fileAssetForName(name));
}

String _folderAssetForName(String name) {
  final folderName = name.toLowerCase().replaceAll('/', '');
  switch (folderName) {
    case 'image':
    case 'images':
    case 'photo':
    case 'photos':
    case 'picture':
    case 'pictures':
    case 'media':
      return 'assets/icons/whitesur/places/folder-images.svg';
    case 'video':
    case 'videos':
    case 'movie':
    case 'movies':
      return 'assets/icons/whitesur/places/folder-videos.svg';
    case 'music':
    case 'audio':
    case 'songs':
      return 'assets/icons/whitesur/places/folder-music.svg';
    case 'document':
    case 'documents':
    case 'doc':
    case 'docs':
      return 'assets/icons/whitesur/places/folder-documents.svg';
    case 'download':
    case 'downloads':
      return 'assets/icons/whitesur/places/folder-download.svg';
    case 'code':
    case 'src':
    case 'source':
    case 'sources':
    case 'lib':
      return 'assets/icons/whitesur/places/folder-code.svg';
    case 'tmp':
    case 'temp':
    case 'cache':
      return 'assets/icons/whitesur/places/folder-temp.svg';
    default:
      return 'assets/icons/whitesur/places/folder.svg';
  }
}

String _fileAssetForName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'assets/icons/whitesur/mimes/application-image-jpg.svg';
    case 'png':
      return 'assets/icons/whitesur/mimes/image-png.svg';
    case 'svg':
      return 'assets/icons/whitesur/mimes/image-svg+xml.svg';
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'ico':
    case 'tiff':
    case 'avif':
      return 'assets/icons/whitesur/mimes/image-x-generic.svg';
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'wmv':
    case 'flv':
    case 'webm':
    case 'm4v':
      return 'assets/icons/whitesur/mimes/video-x-generic.svg';
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'aac':
    case 'ogg':
    case 'm4a':
    case 'wma':
      return 'assets/icons/whitesur/mimes/audio-x-generic.svg';
    case 'pdf':
      return 'assets/icons/whitesur/mimes/application-pdf.svg';
    case 'doc':
    case 'docx':
      return 'assets/icons/whitesur/mimes/x-office-document.svg';
    case 'xls':
    case 'xlsx':
    case 'csv':
      return 'assets/icons/whitesur/mimes/x-office-spreadsheet.svg';
    case 'ppt':
    case 'pptx':
      return 'assets/icons/whitesur/mimes/x-office-presentation.svg';
    case 'txt':
    case 'log':
      return 'assets/icons/whitesur/mimes/text-x-generic.svg';
    case 'md':
      return 'assets/icons/whitesur/mimes/text-markdown.svg';
    case 'html':
      return 'assets/icons/whitesur/mimes/text-html.svg';
    case 'css':
      return 'assets/icons/whitesur/mimes/text-css.svg';
    case 'js':
    case 'jsx':
      return 'assets/icons/whitesur/mimes/text-x-javascript.svg';
    case 'ts':
    case 'tsx':
      return 'assets/icons/whitesur/mimes/text-x-typescript.svg';
    case 'dart':
    case 'go':
    case 'rs':
    case 'java':
    case 'c':
    case 'cpp':
    case 'h':
    case 'swift':
    case 'kt':
      return _typedCodeAsset(ext);
    case 'py':
      return 'assets/icons/whitesur/mimes/text-x-python.svg';
    case 'rb':
    case 'php':
      return _typedScriptAsset(ext);
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'assets/icons/whitesur/mimes/application-x-shellscript.svg';
    case 'json':
      return 'assets/icons/whitesur/mimes/application-json.svg';
    case 'yaml':
    case 'yml':
      return 'assets/icons/whitesur/mimes/application-yaml.svg';
    case 'toml':
    case 'xml':
      return _typedMarkupAsset(ext);
    case 'sql':
      return 'assets/icons/whitesur/mimes/text-x-sql.svg';
    case 'zip':
    case '7z':
      return 'assets/icons/whitesur/mimes/application-x-zip.svg';
    case 'tar':
    case 'tgz':
      return 'assets/icons/whitesur/mimes/application-x-tar.svg';
    case 'gz':
      return 'assets/icons/whitesur/mimes/application-x-gzip.svg';
    case 'rar':
      return 'assets/icons/whitesur/mimes/application-x-rar.svg';
    case 'bz2':
      return 'assets/icons/whitesur/mimes/application-x-bzip.svg';
    case 'xz':
      return 'assets/icons/whitesur/mimes/application-x-xz-compressed-tar.svg';
    case 'exe':
    case 'msi':
      return 'assets/icons/whitesur/mimes/application-vnd.microsoft.portable-executable.svg';
    case 'dmg':
    case 'deb':
    case 'rpm':
    case 'app':
      return 'assets/icons/whitesur/mimes/package-x-generic.svg';
    default:
      return 'assets/icons/whitesur/mimes/application-blank.svg';
  }
}

String _typedCodeAsset(String ext) {
  switch (ext) {
    case 'go':
      return 'assets/icons/whitesur/mimes/text-x-go.svg';
    case 'rs':
      return 'assets/icons/whitesur/mimes/text-rust.svg';
    case 'java':
      return 'assets/icons/whitesur/mimes/text-x-java.svg';
    case 'c':
      return 'assets/icons/whitesur/mimes/text-x-c.svg';
    case 'cpp':
      return 'assets/icons/whitesur/mimes/text-x-cpp.svg';
    case 'h':
      return 'assets/icons/whitesur/mimes/text-x-chdr.svg';
    case 'kt':
      return 'assets/icons/whitesur/mimes/text-x-kotlin.svg';
    default:
      return 'assets/icons/whitesur/mimes/text-x-script.svg';
  }
}

String _typedScriptAsset(String ext) {
  switch (ext) {
    case 'rb':
      return 'assets/icons/whitesur/mimes/text-x-ruby.svg';
    case 'php':
      return 'assets/icons/whitesur/mimes/text-x-php.svg';
    default:
      return 'assets/icons/whitesur/mimes/text-x-script.svg';
  }
}

String _typedMarkupAsset(String ext) {
  switch (ext) {
    case 'xml':
      return 'assets/icons/whitesur/mimes/text-xml.svg';
    case 'toml':
      return 'assets/icons/whitesur/mimes/application-toml.svg';
    default:
      return 'assets/icons/whitesur/mimes/text-x-generic.svg';
  }
}
