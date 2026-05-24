// 文件可见性工具：统一处理是否隐藏以 . 开头的文件和目录。

import 'package:remote_storage/models/s3_objects.dart';

List<ObjectInfo> filterVisibleObjects(
  List<ObjectInfo> objects, {
  required bool hideDotFiles,
}) {
  if (!hideDotFiles) {
    return objects;
  }
  return objects.where((object) => !isHiddenDotObject(object)).toList();
}

bool isHiddenDotObject(ObjectInfo object) {
  final name = object.displayName.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    return false;
  }
  return name.startsWith('.');
}
