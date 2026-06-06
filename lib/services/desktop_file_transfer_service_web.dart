// Web file-transfer fallback keeps desktop-only native clipboard paths disabled.

import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class DesktopFileTransferService {
  DesktopFileTransferService._();

  static final DesktopFileTransferService instance =
      DesktopFileTransferService._();

  Future<List<String>> localFilePathsFromDrop(PerformDropEvent event) async {
    return const <String>[];
  }

  Future<List<String>> localFilePathsFromClipboard() async {
    return const <String>[];
  }

  Future<void> writeLocalFilesToClipboard(List<String> localPaths) async {}
}
